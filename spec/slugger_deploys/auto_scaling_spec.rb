require 'spec_helper'
require 'fog/aws'

describe SluggerDeploys::AutoScaling do
  let!(:launch_config) do
    SluggerDeploys::LaunchConfiguration.new! do
      name :my_launch_config_for_auto_scaling
      ami 'ami :) :) :)'
      instance_type 'm1.large'
      stub(:sleep)
    end.tap(&:create)
  end

  subject { described_class.new! }
  before { subject.stub(:sleep) }

  describe '#create!' do
    context 'when none of the required options are set' do
      it 'raises an error' do
        expect { subject.create! }.to raise_error
      end
    end

    context 'when some of the required options are set' do
      before { subject.max_size 101 }

      it 'raises an error' do
        expect { subject.create! }.to raise_error
      end
    end

    context 'when all of the required options are set' do
      let!(:launch_configuration) do
        SluggerDeploys::LaunchConfiguration.new! do
          ami 'fake_ami'
          instance_type 'm1.large'
          stub(:sleep)
        end
      end
      let(:availability_zone) { 'US' }
      let(:min_size) { 1 }
      let(:max_size) { 10 }
      let(:options) { { :name => :my_group,
                        :launch_configuration => launch_configuration.name,
                        :availability_zones => [availability_zone],
                        :min_size => 1,
                        :max_size => 10 } }

      subject { SluggerDeploys::AutoScaling.new!(options) }
      before { subject.tag :my_group => '1' }

      context 'when the launch configuration is not known' do
        before { subject.instance_variable_set(:@launch_configuration, nil) }
        it 'raises an error' do
          expect { subject.create! }.to raise_error
        end
      end

      context 'when the launch configuration is known' do
        before do
          launch_configuration.create!
        end

        it 'creates an auto-scaling group' do
          expect { subject.create! }
              .to change { subject.send(:conn).data[:auto_scaling_groups][subject.aws_identifier].class.to_s }
              .from('NilClass')
              .to('Hash')
        end
      end
    end
  end

  describe '#destroy!' do
    let(:aws_identifier) { subject.aws_identifier }
    subject { SluggerDeploys::AutoScaling.new }

    context 'when there is no such auto-scaling group' do
      it 'raises an error' do
        expect { subject.destroy! }
            .to raise_error(Fog::AWS::AutoScaling::ValidationError)
      end
    end

    context 'when the auto-scaling group exists' do
      before { subject.send(:conn).data[:auto_scaling_groups][aws_identifier] = aws_identifier }

      it 'deletes the auto-scaling group' do
        expect { subject.destroy! }
            .to change { subject.send(:conn).data[:auto_scaling_groups][aws_identifier] }
            .from(aws_identifier)
            .to(nil)
      end
    end
  end

  describe '#create' do
    context 'when the aws_identifier is nil' do
      subject { described_class.new!(:name => 'nonsense') }

      it 'raises an error' do
        expect { subject.create }.to raise_error
      end
    end

    context 'when the aws_identifier is present' do
      subject { described_class.new!(:name => 'nonsense2') }

      context 'when the model already exists' do
        before { described_class.stub(:exists?).and_return(true) }

        it 'does not create it' do
          subject.should_not_receive(:create!)
          subject.create
        end
      end

      context 'when the model does not already exist' do
        before { described_class.stub(:exists?).and_return(false) }

        it 'creates it' do
          subject.should_receive(:create!)
          subject.create
        end
      end
    end
  end

  describe '#destroy' do
    subject { described_class.new!(:name => 'nonsense2') }

    context 'when the model already exists' do
      before { described_class.stub(:exists?).and_return(true) }

      it 'destroys it' do
        subject.should_receive(:destroy!)
        subject.destroy
      end
    end

    context 'when the model does not exist' do
      before { described_class.stub(:exists?).and_return(false) }

      it 'does not destroy it' do
        subject.should_not_receive(:destroy!)
        subject.destroy
      end
    end
  end

  describe '.exists?' do
    subject { described_class }

    context 'when the argument exists' do
      let!(:existing) {
        conf = launch_config
        subject.new! do
          min_size  1
          max_size  3
          availability_zones  'us-east-1'
          launch_configuration conf.name
          stub(:sleep)
        end.tap(&:create)
      }

      it 'returns true' do
        subject.exists?(existing.aws_identifier).should be_true
      end
    end

    context 'when the argument does not exist' do
      before do
        described_class.new! do
          name :exists_test_name
          aws_identifier 'does-not-exist'
          stub(:sleep)
        end.destroy! rescue nil
      end

      it 'returns false' do
        subject.exists?('does-not-exist').should be_false
      end
    end
  end

  describe '.all' do
    subject { described_class }

    def destroy_all
      SluggerDeploys::AutoScaling.instances.values.each do |instance|
        instance.destroy! rescue nil
      end
    end

    after { destroy_all }

    context 'when there are no auto scaling groups' do
      before { destroy_all }

      its(:all) { should be_empty }
    end

    context 'when there are auto scaling groups' do

      let!(:insts) do
        [
          {
            :min_size => 1,
            :max_size => 3,
            :availability_zones => 'us-east-1',
            :launch_configuration => launch_config.name
          },
          {
            :min_size => 2,
            :max_size => 4,
            :availability_zones => 'us-east-2',
            :launch_configuration => launch_config.name,
            :tag => { :my_tag => :is_sweet }
          }
        ].map { |hash| subject.new!(hash).tap { |inst| inst.stub(:sleep); inst.create! } }
      end

      it 'returns each of them' do
        subject.all.map(&:min_size).should == [1, 2]
        subject.all.map(&:max_size).should == [3, 4]
        subject.all.map(&:tags).should == [{
            "GitSha" => SluggerDeploys::Util.git_sha,
            "Deploy" => insts.first.name.to_s
          },
          {
            "GitSha" => SluggerDeploys::Util.git_sha,
            "Deploy" => insts.last.name.to_s,
            :my_tag => :is_sweet
          }
        ]
      end
    end
  end

  describe '.from_hash' do
    context 'when the auto scaling group has not been initialized' do
      let(:auto_scaling) { described_class.from_hash(hash) }

      let(:hash) do
        {
          'AutoScalingGroupName' => 'test-auto-scaling',
          'AvailabilityZones' => 'us-east-1',
          'LaunchConfigurationName' => launch_config.aws_identifier,
          'MinSize' => 1,
          'MaxSize' => 2
        }
      end

      it 'creates a new auto scaling group with the specified values' do
        auto_scaling.aws_identifier.should == 'test-auto-scaling'
        auto_scaling.availability_zones.should == 'us-east-1'
        auto_scaling.launch_configuration.should == launch_config
        auto_scaling.min_size.should == 1
        auto_scaling.max_size.should == 2
      end

      it 'generates a name' do
        auto_scaling.name.to_s.should start_with 'AutoScaling_'
      end
    end

    context 'when the auto scaling group has already been initialized' do
      let(:old_hash) do
        {
          'AutoScalingGroupName' => 'this-aws-id-abc-123',
          'MinSize' => 16
        }
      end
      let(:new_hash) { old_hash.merge('MaxSize' => 40) }
      let!(:existing) { described_class.from_hash(old_hash) }
      let(:new) { described_class.from_hash(new_hash) }

      it 'updates its values' do
        expect { new }.to change { described_class.instances.length }.by(1)
        new.aws_identifier.should == 'this-aws-id-abc-123'
        new.min_size.should == 16
        new.max_size.should == 40
      end
    end
  end

  describe '.latest_for_tag' do
    subject { SluggerDeploys::AutoScaling }

    before { subject.stub(:all).and_return(groups) }

    context 'when there are no groups' do
      let(:groups) { [] }

      it 'returns nil' do
        subject.latest_for_tag('Deploy', 'my-deploy').should be_nil
      end
    end

    context 'when there is at least one group' do
      context 'but none of the groups satisfy the query' do
        let(:group1) { double(:tags => { 'Deploy' => 'not-the-correct-deploy' }) }
        let(:group2) { double(:tags => {}) }
        let(:group3) { double(:tags => { 'deploy' => 'my-deploy' }) }
        let(:groups) { [group1, group2, group3] }

        it 'returns nil' do
          subject.latest_for_tag('Deploy', 'my-deploy').should be_nil
        end
      end

      context 'and one group satisfies the query' do
        let(:group1) { double(:tags => { 'Deploy' => 'my-deploy' },
                            :created_time => Time.parse('01-01-2013')) }
        let(:group2) { double(:tags => { 'Non' => 'Sense'}) }
        let(:groups) { [group1, group2] }

        it 'returns that group' do
          subject.latest_for_tag('Deploy', 'my-deploy').should == group1
        end
      end

      context 'and many groups satisfy the query' do
        let(:group1) { double(:tags => { 'Deploy' => 'my-deploy' },
                            :created_time => Time.parse('01-01-2013')) }
        let(:group2) { double(:tags => { 'Deploy' => 'my-deploy' },
                            :created_time => Time.parse('02-01-2013')) }
        let(:group3) { double(:tags => { 'Non' => 'Sense'}) }
        let(:groups) { [group1, group2, group3] }

        it 'returns the group that was created last' do
          subject.latest_for_tag('Deploy', 'my-deploy').should == group2
        end
      end
    end
  end

  describe '#all_instances' do
    let(:auto_scaling) {
      described_class.new(
        :name => :all_instances_asg,
        :availability_zones => [],
        :max_size => 10,
        :min_size => 4,
        :launch_configuration => launch_config.name
      )
    }

    before { auto_scaling.stub(:sleep); auto_scaling.create! }
    after { auto_scaling.destroy! }

    it 'returns a list of instances associated with the group' do
      auto_scaling.all_instances.length.should == 4
      auto_scaling.all_instances.should be_all { |inst| inst.is_a?(SluggerDeploys::Instance) }
    end
  end
end
