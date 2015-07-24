require 'spec_helper'

describe Aerosol::LaunchConfiguration do
  subject do
    described_class.new do
      name :my_launch_config
      image_id 'ami-123'
      instance_type 'super-cool-instance-type'
      user_data <<-END_OF_STRING
        #!/bin/bash
        rm -rf /
      END_OF_STRING
    end
  end
  before { subject.stub(:sleep) }

  describe "#launch_configuration_name" do
    context "with no namespace set" do
      let(:identifier) { "my_launch_config-#{Aerosol::Util.git_sha}" }
      it "returns a normal identifier" do
        expect(subject.launch_configuration_name).to eq(identifier)
      end
    end

    context "with a namespace set" do
      let(:namespace) { "test" }
      let(:identifier) { "#{namespace}-my_launch_config-#{Aerosol::Util.git_sha}" }

      before { Aerosol.namespace namespace }
      after { Aerosol.instance_variable_set(:"@namespace", nil) }

      it "returns a namespaced identifier" do
        expect(subject.launch_configuration_name).to eq(identifier)
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
      before { subject.instance_variable_set(:@image_id, nil) }

      it 'raises an error' do
        expect { subject.create! }.to raise_error
      end
    end

    context 'when everything is present' do
      context 'and the launch configuration already exists' do
        it 'raises an error' do
          Aerosol::AWS.auto_scaling.stub_responses(
            :create_launch_configuration,
            Aws::AutoScaling::Errors::AlreadyExists
          )
          expect { subject.create! }.to raise_error
        end
      end

      context 'and the launch configuration does not exist yet' do
        after { subject.destroy! rescue nil }

        it 'creates the launch configuration group' do
          Aerosol::AWS.auto_scaling.stub_responses(:create_launch_configuration, [])
          expect { subject.create! }.to_not raise_error
        end
      end
    end
  end

  describe '#destroy!' do
    context 'when the launch_configuration_name is nil' do

      it 'raises an error' do
        allow(subject).to receive(:launch_configuration_name).and_return(nil)
        Aerosol::AWS.auto_scaling.stub_responses(:delete_launch_configuration, [])
        expect { subject.destroy! }.to raise_error
      end
    end

    context 'when the launch_configuration_name is present' do
      context 'but the launch configuration does not exist' do
        it 'raises an error' do
          Aerosol::AWS.auto_scaling.stub_responses(
            :delete_launch_configuration,
            Aws::AutoScaling::Errors::ValidationError
          )
          expect { subject.destroy! }.to raise_error
        end
      end

      context 'and the launch configuration exists' do
        it 'deletes the launch configuration' do
          Aerosol::AWS.auto_scaling.stub_responses(:delete_launch_configuration, [])
          expect { subject.destroy! }.to_not raise_error
        end
      end
    end
  end

  describe '#create' do
    context 'when the launch_configuration_name is nil' do
      subject do
        described_class.new! do
          name :random_test_name
          image_id 'test-ami-who-even-cares-really'
          instance_type 'm1.large'
        end
      end

      it 'raises an error' do
        allow(subject).to receive(:launch_configuration_name).and_return(nil)
        Aerosol::AWS.auto_scaling.stub_responses(:create_launch_configuration, [])
        Aerosol::AWS.auto_scaling.stub_responses(:describe_launch_configurations, {
          launch_configurations: [], next_token: nil
        })
        expect { subject.create }.to raise_error
      end
    end

    context 'when the launch_configuration_name is present' do
      subject do
        described_class.new! do
          name :random_test_name_2
          image_id 'test-ami-who-even-cares-really'
          instance_type 'm1.large'
        end
      end

      context 'but the launch configuration already exists' do
        it 'does not call #create!' do
          Aerosol::AWS.auto_scaling.stub_responses(:describe_launch_configurations, {
            launch_configurations: [{
              launch_configuration_name: subject.launch_configuration_name,
              image_id: 'ami-1235535',
              instance_type: 'm3.large',
              created_time: Time.at(1)
            }],
            next_token: nil
          })
          expect(subject).to_not receive(:create!)
          subject.create
        end
      end

      context 'and the launch configuration does not yet exist' do
        it 'creates it' do
          Aerosol::AWS.auto_scaling.stub_responses(:describe_launch_configurations, {
            launch_configurations: [],
            next_token: nil
          })
          subject.should_receive(:create!)
          subject.create
        end
      end
    end
  end

  describe '#destroy' do
    subject do
      described_class.new! do
        name :random_test_name_3
        image_id 'awesome-ami'
        instance_type 'm1.large'
      end
    end

    context 'when the launch_configuration_name is nil' do
      it 'raises an error' do
        allow(subject).to receive(:launch_configuration_name).and_return(nil)
        Aerosol::AWS.auto_scaling.stub_responses(:describe_launch_configurations, {
          launch_configurations: [],
          next_token: nil
        })
        expect { subject.create }.to raise_error(ArgumentError)
      end
    end

    context 'when the launch_configuration_name is present' do
      context 'and the launch configuration already exists' do

        it 'calls #destroy!' do
          Aerosol::AWS.auto_scaling.stub_responses(:describe_launch_configurations, {
            launch_configurations: [{
              launch_configuration_name: subject.launch_configuration_name,
              image_id: 'ami-1235535',
              instance_type: 'm3.large',
              created_time: Time.at(1)
            }],
            next_token: nil
          })
          subject.should_receive(:destroy!)
          subject.destroy
        end
      end

      context 'but the launch configuration does not yet exist' do
        it 'does not call #destroy!' do
          Aerosol::AWS.auto_scaling.stub_responses(:describe_launch_configurations, {
            launch_configurations: [],
            next_token: nil
          })
          subject.should_not_receive(:destroy!)
          subject.destroy
        end
      end
    end
  end

  describe '.exists?' do
    subject { described_class }
    let(:instance) do
      subject.new! do
        name :exists_test_name
        image_id 'ami123'
        instance_type 'm1.large'
        stub(:sleep)
      end
    end

    context 'when the argument exists' do
      it 'returns true' do
        Aerosol::AWS.auto_scaling.stub_responses(:describe_launch_configurations, {
          launch_configurations: [{
            launch_configuration_name: instance.launch_configuration_name,
            image_id: 'ami-1235535',
            instance_type: 'm3.large',
            created_time: Time.at(1)
          }],
          next_token: nil
        })
        subject.exists?(instance.launch_configuration_name).should be_true
      end
    end

    context 'when the argument does not exist' do
      let(:instance) { described_class.new!   }

      it 'returns false' do
        Aerosol::AWS.auto_scaling.stub_responses(:describe_launch_configurations, {
          launch_configurations: [],
          next_token: nil
        })
        subject.exists?(instance.launch_configuration_name).should be_false
      end
    end
  end

  describe '.request_all' do
    describe 'repeats until no NextToken' do
      it 'should include both autoscaling groups lists' do
        Aerosol::AWS.auto_scaling.stub_responses(:describe_launch_configurations, [
          {
            launch_configurations: [
              {
                launch_configuration_name: '1',
                image_id: 'ami-1235535',
                instance_type: 'm3.large',
                created_time: Time.at(1)
              }, {
                launch_configuration_name: '4',
                image_id: 'ami-1235535',
                instance_type: 'm3.large',
                created_time: Time.at(1)
              }
            ],
            next_token: 'yes'
          },
          {
            launch_configurations: [
              {
                launch_configuration_name: '2',
                image_id: 'ami-1235535',
                instance_type: 'm3.large',
                created_time: Time.at(1)
              }, {
                launch_configuration_name: '3',
                image_id: 'ami-1235535',
                instance_type: 'm3.large',
                created_time: Time.at(1)
              }
            ],
            next_token: nil
          }
        ])
        expect(Aerosol::LaunchConfiguration.request_all.map(&:launch_configuration_name)).to eq(['1','4','2','3'])
      end
    end
  end

  describe '.all' do
    subject { described_class }

    context 'when there are no launch configurations' do
      before do
        Aerosol::AWS.auto_scaling.stub_responses(:describe_launch_configurations, [
          { launch_configurations: [], next_token: nil }
        ])
      end
      its(:all) { should be_empty }
    end

    context 'when there are launch configurations' do
      let(:insts) {
        [
          {
            launch_configuration_name: 'test',
            image_id: 'ami1',
            instance_type: 'm1.large',
            created_time: Time.at(1)
          },
          {
            launch_configuration_name: 'test2',
            image_id: 'ami2',
            instance_type: 'm1.large',
            created_time: Time.at(1)
          }
        ]
      }

      it 'returns each of them' do
        Aerosol::AWS.auto_scaling.stub_responses(:describe_launch_configurations, {
          launch_configurations: insts,
          next_token: nil
        })
        subject.all.map(&:image_id).should == %w[ami1 ami2]
        subject.all.map(&:instance_type).should == %w[m1.large m1.large]
      end
    end
  end

  describe '.from_hash' do
    context 'when the launch configuration has not been initialized' do
      subject { described_class.from_hash(hash) }
      let(:hash) do
        {
          launch_configuration_name: '~test-launch-config~',
          image_id: 'ami-123',
          instance_type: 'm1.large',
          security_groups: [],
          user_data: 'echo hi',
          iam_instance_profile: nil,
          kernel_id: 'kernel-id',
          key_name: 'key-name',
          spot_price: '0.04',
        }
      end

      it 'creates a new launch configuration with the specified values' do
        subject.launch_configuration_name.should == '~test-launch-config~'
        subject.image_id.should == 'ami-123'
        subject.instance_type.should == 'm1.large'
        subject.security_groups.should be_empty
        subject.user_data.should == 'echo hi'
        subject.iam_instance_profile.should be_nil
        subject.kernel_id.should == 'kernel-id'
        subject.spot_price.should == '0.04'
        subject.from_aws = true
      end

      it 'generates a name' do
        subject.name.to_s.should start_with 'LaunchConfiguration_'
      end
    end

    context 'when the launch configuration has already been initialized' do
      let(:old_hash) do
        {
          launch_configuration_name: 'this-aws-id-abc-123',
          image_id: 'ami-456',
        }
      end
      let(:new_hash) { old_hash.merge(instance_type: 'm1.large') }
      let!(:existing) { described_class.from_hash(old_hash) }
      let(:new) { described_class.from_hash(new_hash) }

      it 'makes a new instance' do
        expect { new }.to change { described_class.instances.length }.by(1)
        new.launch_configuration_name.should == 'this-aws-id-abc-123'
        new.image_id.should == 'ami-456'
      end
    end
  end

  describe '#corrected_user_data' do
    let(:encoded_user_data_string) { Base64.encode64('test') }

    context 'when the user_data is a String' do
      subject do
        described_class.new do
          name :corrected_user_data
          user_data 'test'
        end
      end

      it 'correctly encodes to base64' do
        expect(subject.corrected_user_data).to eq(encoded_user_data_string)
      end
    end

    context 'when the user_data is a Proc' do
      subject do
        described_class.new do
          name :corrected_user_data_2
          user_data { 'test' }
        end
      end

      it 'correctly encodes to base64' do
        expect(subject.corrected_user_data).to eq(encoded_user_data_string)
      end
    end
  end
end
