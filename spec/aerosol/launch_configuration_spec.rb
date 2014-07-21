require 'spec_helper'

describe Aerosol::LaunchConfiguration do
  subject do
    described_class.new do
      name :my_launch_config
      ami 'ami-123'
      instance_type 'super-cool-instance-type'
      user_data <<-END_OF_STRING
        #!/bin/bash
        rm -rf /
      END_OF_STRING
    end
  end
  before { subject.stub(:sleep) }

  describe "#aws_identifier" do
    context "with no namespace set" do
      let(:identifier) { "my_launch_config-#{Aerosol::Util.git_sha}" }
      it "returns a normal identifier" do
        expect(subject.aws_identifier).to eq(identifier)
      end
    end

    context "with a namespace set" do
      let(:namespace) { "test" }
      let(:identifier) { "#{namespace}-my_launch_config-#{Aerosol::Util.git_sha}" }

      before { Aerosol.namespace namespace }
      after { Aerosol.instance_variable_set(:"@namespace", nil) }

      it "returns a namespaced identifier" do
        expect(subject.aws_identifier).to eq(identifier)
      end
    end
  end

  describe '#security_group' do
    subject { described_class.new!(:name => 'conf-conf-conf') }

    it 'adds the argument to the list of security groups' do
      expect { subject.security_group 'my group' }
          .to change { subject.security_groups.length }
          .by 1
    end

    it 'does not the default security group' do
      expect { subject.security_group 'other test' }
          .to_not change { described_class.default_values[:security_groups] }
    end
  end

  describe '#create!' do
    context 'when some required fields are nil' do
      before { subject.instance_variable_set(:@ami, nil) }

      it 'raises an error' do
        expect { subject.create! }.to raise_error
      end
    end

    context 'when everything is present' do
      context 'and the launch configuration already exists' do
        before { subject.create! rescue nil }
        after { subject.destroy! rescue nil }

        it 'raises an error' do
          expect { subject.create! }.to raise_error
        end
      end

      context 'and the launch configuration does not exist yet' do
        after { subject.destroy! rescue nil }

        it 'creates the launch configuration group' do
          expect { subject.create! }.to_not raise_error
        end

        it 'fixes the user data spacing' do
          subject.send(:conn).should_receive(:create_launch_configuration)
                             .with('ami-123', 'super-cool-instance-type',
                                   subject.aws_identifier,
                                   'SecurityGroups' => [],
                                   'UserData' => "#!/bin/bash\nrm -rf /\n")
          subject.create!
        end
      end
    end
  end

  describe '#destroy!' do
    context 'when the aws_identifier is nil' do
      before { subject.instance_variable_set(:@aws_identifier, nil) }

      it 'raises an error' do
        expect { subject.destroy! }.to raise_error
      end
    end

    context 'when the aws_identifier is present' do
      context 'but the launch configuration does not exist' do
        it 'raises an error' do
          expect { subject.destroy! }.to raise_error
        end
      end

      context 'and the launch configuration exists' do
        before { subject.create! }

        it 'deletes the launch configuration' do
          expect { subject.destroy! }.to_not raise_error
        end
      end
    end
  end

  describe '#create' do
    context 'when the aws_identifier is nil' do
      subject { described_class.new!(:name => :random_test_name) }

      it 'raises an error' do
        expect { subject.create }.to raise_error
      end
    end

    context 'when the aws_identifier is present' do
      subject do
        described_class.new! do
          name :random_test_name_2
          ami 'test-ami-who-even-cares-really'
          instance_type 'm1.large'
        end
      end

      context 'but the launch configuration already exists' do
        before { subject.create! }

        it 'does not call #create!' do
          subject.should_not_receive(:create!)
          subject.create
        end
      end

      context 'and the launch configuration does not yet exist' do
        before { subject.destroy }

        it 'creates it' do
          subject.should_receive(:create!)
          subject.create
        end
      end
    end
  end

  describe '#destroy' do
    context 'when the aws_identifier is nil' do
      subject { described_class.new!(:name => :random_test_name_3) }

      it 'raises an error' do
        expect { subject.create }.to raise_error
      end
    end

    context 'when the aws_identifier is present' do
      subject do
        described_class.new! do
          name :random_test_name_4
          ami 'awesome-ami'
          instance_type 'm1.large'
        end
      end

      context 'and the launch configuration already exists' do
        before { subject.create! }

        it 'calls #destroy!' do
          subject.should_receive(:destroy!)
          subject.destroy
        end
      end

      context 'but the launch configuration does not yet exist' do
        before { subject.destroy! rescue nil }

        it 'does not call #destroy!' do
          subject.should_not_receive(:destroy!)
          subject.destroy
        end
      end
    end
  end

  describe '.exists?' do
    subject { described_class }

    context 'when the argument exists' do
      let(:instance) do
        subject.new! do
          name :exists_test_name
          ami 'ami123'
          instance_type 'm1.large'
          stub(:sleep)
        end.tap(&:create!)
      end

      it 'returns true' do
        subject.exists?(instance.aws_identifier).should be_true
      end
    end

    context 'when the argument does not exist' do
      let(:instance) { described_class.new!   }

      it 'returns false' do
        subject.exists?(instance.aws_identifier).should be_false
      end
    end
  end

  describe '.all' do
    subject { described_class }

    def destroy_all
      Aerosol::LaunchConfiguration.instances.values.each do |instance|
        instance.destroy! rescue nil
      end
    end

    after { destroy_all }

    context 'when there are no launch configurations' do
      before { destroy_all }

      its(:all) { should be_empty }
    end

    context 'when there are launch configurations' do

      before do
        [
          {
            :ami => 'ami1',
            :instance_type => 'm1.large'
          },
          {
            :ami => 'ami2',
            :instance_type => 'm1.large'
          }
        ].each { |hash| subject.new!(hash).tap { |inst| inst.stub(:sleep) }.create! }
      end

      it 'returns each of them' do
        subject.all.map(&:ami).should == %w[ami1 ami2]
        subject.all.map(&:instance_type).should == %w[m1.large m1.large]
      end
    end
  end

  describe '.from_hash' do
    context 'when the launch configuration has not been initialized' do
      subject { described_class.from_hash(hash) }
      let(:hash) do
        {
          'LaunchConfigurationName' => '~test-launch-config~',
          'ImageId' => 'ami-123',
          'InstanceType' => 'm1.large',
          'SecurityGroups' => [],
          'UserData' => 'echo hi',
          'IamInstanceProfile' => nil,
          'KernelId' => 'kernel-id',
          'KeyName' => 'key-name',
          'SpotPrice' => '0.04',
        }
      end

      it 'creates a new launch configuration with the specified values' do
        subject.aws_identifier.should == '~test-launch-config~'
        subject.ami.should == 'ami-123'
        subject.instance_type.should == 'm1.large'
        subject.security_groups.should be_empty
        subject.user_data.should == 'echo hi'
        subject.iam_role.should be_nil
        subject.kernel_id.should == 'kernel-id'
        subject.spot_price.should == '0.04'
      end

      it 'generates a name' do
        subject.name.to_s.should start_with 'LaunchConfiguration_'
      end
    end

    context 'when the launch configuration has already been initialized' do
      let(:old_hash) do
        {
          'LaunchConfigurationName' => 'this-aws-id-abc-123',
          'ImageId' => 'ami-456',
        }
      end
      let(:new_hash) { old_hash.merge('InstanceType' => 'm1.large') }
      let!(:existing) { described_class.from_hash(old_hash) }
      let(:new) { described_class.from_hash(new_hash) }

      it 'updates its values' do
        expect { new }.to change { described_class.instances.length }.by(1)
        new.aws_identifier.should == 'this-aws-id-abc-123'
        new.ami.should == 'ami-456'
      end
    end
  end
end
