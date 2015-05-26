require 'spec_helper'

describe Aerosol::AutoScaling do
  let(:launch_configuration_setup) do
    Aerosol::LaunchConfiguration.new! do
      name :my_launch_config_for_auto_scaling
      image_id 'ami :) :) :)'
      instance_type 'm1.large'
      stub(:sleep)
    end
  end

  let(:launch_configuration) do
    launch_configuration_setup.tap(&:create)
  end

  subject { described_class.new!(&block) }
  let(:previous_launch_configurations) { [] }
  let(:previous_auto_scaling_groups) { [] }

  before do
    subject.stub(:sleep)
    Aerosol::AWS.auto_scaling.stub_responses(:describe_launch_configurations, { launch_configurations: previous_launch_configurations, next_token: nil })
    Aerosol::AWS.auto_scaling.stub_responses(:describe_auto_scaling_groups, { auto_scaling_groups: previous_auto_scaling_groups, next_token: nil })
  end

  let(:block) { Proc.new { } }

  describe "#auto_scaling_group_name" do
    let(:block) { Proc.new { name :my_auto_scaling } }

    context "with no namespace set" do
      let(:identifier) { "my_auto_scaling-#{Aerosol::Util.git_sha}" }
      it "returns a normal identifier" do
        expect(subject.auto_scaling_group_name).to eq(identifier)
      end
    end

    context "with a namespace set" do
      let(:namespace) { "test" }
      let(:identifier) { "#{namespace}-my_auto_scaling-#{Aerosol::Util.git_sha}" }

      before { Aerosol.namespace namespace }
      after { Aerosol.instance_variable_set(:"@namespace", nil) }

      it "returns a namespaced identifier" do
        expect(subject.auto_scaling_group_name).to eq(identifier)
      end
    end
  end

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
      let(:availability_zone) { 'US' }
      let(:min_size) { 1 }
      let(:max_size) { 10 }
      let(:options) {
        {
          :name => :my_group,
          :launch_configuration => launch_configuration.name,
          :availability_zones => [availability_zone],
          :min_size => 1,
          :max_size => 10,
          :vpc_zone_identifier => 'subnet-deadbeef,subnet-00112233'
        }
      }

      subject { Aerosol::AutoScaling.new!(options) }
      before { subject.tag :my_group => '1' }

      context 'when the launch configuration is not known' do
        before { subject.instance_variable_set(:@launch_configuration, nil) }
        it 'raises an error' do
          expect { subject.create! }.to raise_error
        end
      end

      context 'when the launch configuration is known' do
        it 'creates an auto-scaling group' do
          expect(subject.tags).to include('Deploy' => 'my_group')
          subject.create!
        end

        context "when there is a namespace" do
          subject do
            Aerosol.namespace "tags"
            Aerosol::AutoScaling.new!(options)
          end

          after { Aerosol.instance_variable_set(:"@namespace", nil) }

          it "includes the namespace" do
            expect(subject.tags).to include('Deploy' => 'tags-my_group')
          end
        end
      end
    end
  end

  describe '#destroy!' do
    subject { Aerosol::AutoScaling.new }

    context 'when there is no such auto-scaling group' do
      it 'raises an error' do
        Aerosol::AWS.auto_scaling.stub_responses(:delete_auto_scaling_group, Aws::AutoScaling::Errors::ValidationError)

        expect { subject.destroy! }.to raise_error(Aws::AutoScaling::Errors::ValidationError)
      end
    end

    context 'when the auto-scaling group exists' do
      it 'deletes the auto-scaling group' do
        Aerosol::AWS.auto_scaling.stub_responses(:delete_auto_scaling_group, {})
        expect { subject.destroy! }.to_not raise_error
      end
    end
  end

  describe '#create' do
    context 'when the auto_scaling_group_name is nil' do
      subject { described_class.new!(:name => 'nonsense') }

      it 'raises an error' do
        expect { subject.create }.to raise_error
      end
    end

    context 'when the auto_scaling_group_name is present' do
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
      it 'returns true' do
        Aerosol::AWS.auto_scaling.stub_responses(:describe_auto_scaling_groups, { auto_scaling_groups: [{ auto_scaling_group_name: 'test' }], next_token: nil })
        subject.exists?('test').should be_true
      end
    end

    context 'when the argument does not exist' do
      before do
        described_class.new! do
          name :exists_test_name
          auto_scaling_group_name 'does-not-exist'
          stub(:sleep)
        end.destroy! rescue nil
      end

      it 'returns false' do
        subject.exists?('does-not-exist').should be_false
      end
    end
  end

  describe '.request_all' do
    describe 'repeats until no NextToken' do
      it 'should include both autoscaling groups lists' do
        Aerosol::AWS.auto_scaling.stub_responses(:describe_auto_scaling_groups, [
          { auto_scaling_groups: [{ auto_scaling_group_name: '1' }, { auto_scaling_group_name: '4' }], next_token: 'token'},
          { auto_scaling_groups: [{ auto_scaling_group_name: '2' }, { auto_scaling_group_name: '3' }], next_token: nil}
        ])

        expect(Aerosol::AutoScaling.request_all.map(&:auto_scaling_group_name)).to eq(['1','4','2','3'])
      end
    end
  end

  describe '.all' do
    subject { described_class }

    context 'when there are no auto scaling groups' do
      before do
        Aerosol::AWS.auto_scaling.stub_responses(:describe_auto_scaling_groups, [
          { auto_scaling_groups: [], next_token: nil }
        ])
      end
      its(:all) { should be_empty }
    end

    context 'when there are auto scaling groups' do
      let(:insts) {
        [
          {
            auto_scaling_group_name: 'test',
            min_size: 1,
            max_size: 3,
            availability_zones: ['us-east-1'],
            launch_configuration_name: launch_configuration.name.to_s
          },
          {
            auto_scaling_group_name: 'test2',
            min_size: 2,
            max_size: 4,
            availability_zones: ['us-east-2'],
            launch_configuration_name: launch_configuration.name.to_s,
            tags: [{ key: 'my_tag', value: 'is_sweet' }]
          }
        ]
      }

      it 'returns each of them' do
        Aerosol::AWS.auto_scaling.stub_responses(:describe_auto_scaling_groups, {
          auto_scaling_groups: insts,
          next_token: nil
        })
        instances = subject.all
        instances.map(&:min_size).should == [1, 2]
        instances.map(&:max_size).should == [3, 4]
        instances.map(&:tags).should == [{
            'GitSha' => Aerosol::Util.git_sha,
            'Deploy' => instances.first.name.to_s
          },
          {
            'GitSha' => Aerosol::Util.git_sha,
            'Deploy' => instances.last.name.to_s,
            'my_tag' => 'is_sweet'
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
          auto_scaling_group_name: 'test-auto-scaling',
          availability_zones: ['us-east-1'],
          launch_configuration_name: launch_configuration.launch_configuration_name,
          min_size: 1,
          max_size: 2
        }
      end

      it 'creates a new auto scaling group with the specified values' do
        auto_scaling.auto_scaling_group_name.should == 'test-auto-scaling'
        auto_scaling.availability_zones.should == ['us-east-1']
        auto_scaling.launch_configuration.should == launch_configuration
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
          auto_scaling_group_name: 'this-aws-id-abc-123',
          min_size: 16
        }
      end
      let(:new_hash) { old_hash.merge(max_size: 40) }
      let!(:existing) { described_class.from_hash(old_hash) }
      let(:new) { described_class.from_hash(new_hash) }

      it 'makes a new instance' do
        expect { new }.to change { described_class.instances.length }.by(1)
        new.auto_scaling_group_name.should == 'this-aws-id-abc-123'
        new.min_size.should == 16
        new.max_size.should == 40
      end
    end
  end

  describe '.latest_for_tag' do
    subject { Aerosol::AutoScaling }

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
        :launch_configuration => launch_configuration.name
      )
    }
    let(:previous_auto_scaling_groups) {
      [{
        auto_scaling_group_name: 'all_instances_asg',
        instances: [{
          instance_id: 'i-1239013',
          availability_zone: 'us-east-1a',
          lifecycle_state: 'InService',
          health_status: 'GOOD',
          launch_configuration_name: launch_configuration.name.to_s
        }, {
          instance_id: 'i-1239014',
          availability_zone: 'us-east-1a',
          lifecycle_state: 'InService',
          health_status: 'GOOD',
          launch_configuration_name: launch_configuration.name.to_s
        }, {
          instance_id: 'i-1239015',
          availability_zone: 'us-east-1a',
          lifecycle_state: 'InService',
          health_status: 'GOOD',
          launch_configuration_name: launch_configuration.name.to_s
        }, {
          instance_id: 'i-1239016',
          availability_zone: 'us-east-1a',
          lifecycle_state: 'InService',
          health_status: 'GOOD',
          launch_configuration_name: launch_configuration.name.to_s
        }]
      }]
    }

    it 'returns a list of instances associated with the group' do
      auto_scaling.all_instances.length.should == 4
      auto_scaling.all_instances.should be_all { |inst| inst.is_a?(Aerosol::Instance) }
    end
  end
end
