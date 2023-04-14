require 'spec_helper'

describe Aerosol::LaunchTemplate do
  subject do
    described_class.new do
      name :my_launch_template
      image_id 'ami-123'
      instance_type 'super-cool-instance-type'
      user_data <<-END_OF_STRING
        #!/bin/bash
        rm -rf /
      END_OF_STRING
    end
  end
  before { subject.stub(:sleep) }

  describe "#launch_template_name" do
    context "with no namespace set" do
      let(:identifier) { "my_launch_template-#{Aerosol::Util.git_sha}" }
      it "returns a normal identifier" do
        expect(subject.launch_template_name).to eq(identifier)
      end
    end

    context "with a namespace set" do
      let(:namespace) { "test" }
      let(:identifier) { "#{namespace}-my_launch_template-#{Aerosol::Util.git_sha}" }

      before { Aerosol.namespace namespace }
      after { Aerosol.instance_variable_set(:"@namespace", nil) }

      it "returns a namespaced identifier" do
        expect(subject.launch_template_name).to eq(identifier)
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
      context 'and the launch template already exists' do
        it 'raises an error' do
          Aerosol::AWS.compute.stub_responses(
            :create_launch_template,
            Aws::EC2::Errors::AlreadyExists
          )
          expect { subject.create! }.to raise_error
        end
      end

      context 'and the launch template does not exist yet' do
        after { subject.destroy! rescue nil }

        it 'creates the launch template group' do
          Aerosol::AWS.compute.stub_responses(:create_launch_template, [])
          expect { subject.create! }.to_not raise_error
        end
      end
    end
  end

  describe '#destroy!' do
    context 'when the launch_template_name is nil' do

      it 'raises an error' do
        allow(subject).to receive(:launch_template_name).and_return(nil)
        Aerosol::AWS.compute.stub_responses(:delete_launch_template, [])
        expect { subject.destroy! }.to raise_error
      end
    end

    context 'when the launch_template_name is present' do
      context 'but the launch template does not exist' do
        it 'raises an error' do
          Aerosol::AWS.compute.stub_responses(
            :delete_launch_template,
            Aws::EC2::Errors::ValidationError
          )
          expect { subject.destroy! }.to raise_error
        end
      end

      context 'and the launch template exists' do
        it 'deletes the launch template' do
          Aerosol::AWS.compute.stub_responses(:delete_launch_template, [])
          expect { subject.destroy! }.to_not raise_error
        end
      end
    end
  end

  describe '#create' do
    context 'when the launch_template_name is nil' do
      subject do
        described_class.new! do
          name :random_test_name
          image_id 'test-ami-who-even-cares-really'
          instance_type 'm1.large'
        end
      end

      it 'raises an error' do
        allow(subject).to receive(:launch_template_name).and_return(nil)
        Aerosol::AWS.compute.stub_responses(:create_launch_template, [])
        Aerosol::AWS.compute.stub_responses(:describe_launch_templates, {
          launch_templates: [], next_token: nil
        })
        expect { subject.create }.to raise_error
      end
    end

    context 'when the launch_template_name is present' do
      subject do
        described_class.new! do
          name :random_test_name_2
          image_id 'test-ami-who-even-cares-really'
          instance_type 'm1.large'
        end
      end

      context 'but the launch template already exists' do
        it 'does not call #create!' do
          Aerosol::AWS.compute.stub_responses(:describe_launch_templates, {
            launch_templates: [{
              launch_template_name: subject.launch_template_name,
            }],
            next_token: nil
          })
          expect(subject).to_not receive(:create!)
          subject.create
        end
      end

      context 'and the launch template does not yet exist' do
        it 'creates it' do
          Aerosol::AWS.compute.stub_responses(:describe_launch_templates, {
            launch_templates: [],
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

    context 'when the launch_template_name is nil' do
      it 'raises an error' do
        allow(subject).to receive(:launch_template_name).and_return(nil)
        Aerosol::AWS.compute.stub_responses(:describe_launch_templates, {
          launch_templates: [],
          next_token: nil
        })
        expect { subject.create }.to raise_error(ArgumentError)
      end
    end

    context 'when the launch_template_name is present' do
      context 'and the launch template already exists' do

        it 'calls #destroy!' do
          Aerosol::AWS.compute.stub_responses(:describe_launch_templates, {
            launch_templates: [{
              launch_template_name: subject.launch_template_name
            }],
            next_token: nil
          })
          subject.should_receive(:destroy!)
          subject.destroy
        end
      end

      context 'but the launch template does not yet exist' do
        it 'does not call #destroy!' do
          Aerosol::AWS.compute.stub_responses(:describe_launch_templates, {
            launch_templates: [],
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
        Aerosol::AWS.compute.stub_responses(:describe_launch_templates, {
          launch_templates: [{
            launch_template_name: instance.launch_template_name,
          }],
          next_token: nil
        })
        subject.exists?(instance.launch_template_name).should be true
      end
    end

    context 'when the argument does not exist' do
      let(:instance) { described_class.new!   }

      it 'returns false' do
        Aerosol::AWS.compute.stub_responses(:describe_launch_templates, {
          launch_templates: [],
          next_token: nil
        })
        subject.exists?(instance.launch_template_name).should be false
      end
    end
  end

  describe '.request_all' do
    describe 'repeats until no NextToken' do
      it 'should include both autoscaling groups lists' do
        Aerosol::AWS.compute.stub_responses(:describe_launch_templates, [
          {
            launch_templates: [
              { launch_template_name: '1' },
              { launch_template_name: '4' }
            ],
            next_token: 'yes'
          },
          {
            launch_templates: [
              { launch_template_name: '2' },
              { launch_template_name: '3' }
            ],
            next_token: nil
          }
        ])
        expect(Aerosol::LaunchTemplate.request_all.map(&:launch_template_name)).to eq(['1','4','2','3'])
      end
    end
  end

  describe '.all' do
    subject { described_class }

    context 'when there are no launch templates' do
      before do
        Aerosol::AWS.compute.stub_responses(:describe_launch_templates, [
          { launch_templates: [], next_token: nil }
        ])
      end
      it 'is empty' do
        expect(subject.all).to be_empty
      end
    end

    context 'when there are launch templates' do
      let(:insts) {
        [
          { launch_template_name: 'test' },
          { launch_template_name: 'test2' }
        ]
      }

      it 'returns each of them' do
        Aerosol::AWS.compute.stub_responses(:describe_launch_templates, {
          launch_templates: insts,
          next_token: nil
        })
        subject.all.map(&:launch_template_name).should == %w[test test2]
      end
    end
  end

  describe '.from_hash' do
    context 'when the launch template has not been initialized' do
      subject { described_class.from_hash(hash) }
      let(:hash) do
        {
          launch_template_name: '~test-launch-config~',
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

      it 'creates a new launch template with the specified values' do
        subject.launch_template_name.should == '~test-launch-config~'
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
        subject.name.to_s.should start_with 'LaunchTemplate_'
      end
    end

    context 'when the launch template has already been initialized' do
      let(:old_hash) do
        {
          launch_template_name: 'this-aws-id-abc-123',
          image_id: 'ami-456',
        }
      end
      let(:new_hash) { old_hash.merge(instance_type: 'm1.large') }
      let!(:existing) { described_class.from_hash(old_hash) }
      let(:new) { described_class.from_hash(new_hash) }

      it 'makes a new instance' do
        expect { new }.to change { described_class.instances.length }.by(1)
        new.launch_template_name.should == 'this-aws-id-abc-123'
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

  describe '#meta_data' do
    subject do
      described_class.new do
        name :my_launch_template
        meta_data('Test' => '1')
      end
    end

    it 'returns the hash' do
      expect(subject.meta_data['Test']).to eq('1')
    end
  end

  describe 'instance_market_options' do
    context 'When spot price is unlimited' do
      subject do
        described_class.new do
          name :unlimited_spot_request_launch_template
          request_spot true
        end
      end

      it 'returns a simple instance market option hash without a spot price' do
        expect(subject.instance_market_options).to eq({market_type: 'spot'})
        Aerosol::AWS.compute.stub_responses(:create_launch_template, [])
        
      end
    end

    context 'When spot price is set and request_spot is true' do
      subject do
        described_class.new do
          name :limited_spot_request_launch_template
          request_spot true
          spot_price 1.23
        end
      end

      it 'returns a simple instance market option hash with a matching spot price' do
        expected_hash = {market_type: 'spot', spot_options: {max_price: 1.23}}
        expect(subject.instance_market_options).to eq(expected_hash)
      end
    end

    context 'When spot price is set and request_spot is unset' do
      subject do
        described_class.new do
          name :limited_spot_request_launch_template
          spot_price 1.23
        end
      end

      it 'returns a simple instance market option hash with a matching spot price' do
        expected_hash = {market_type: 'spot', spot_options: {max_price: 1.23}}
        expect(subject.instance_market_options).to eq(expected_hash)
      end
    end

    context 'When spot price and request_spot are unset' do
      subject do
        described_class.new do
          name :limited_spot_request_launch_template
        end
      end

      it 'returns a simple instance market option hash with a matching spot price' do
        expect(subject.instance_market_options).to be_nil
      end
    end
  end
end
