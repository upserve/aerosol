require 'spec_helper'

describe Aerosol::Instance do
  let(:launch_configuration) do
    Aerosol::LaunchConfiguration.new!({
      name: 'launch_config_for_instances',
      image_id: 'ami-123-abc',
      instance_type: 'm1.large'
    })
  end

  describe '.all' do
    subject { described_class.all }

    context 'when there are no instances' do
      it { should be_empty }
    end

    context 'when there are instances' do
      it 'materializes each of them into an object' do
        Aerosol::AWS.auto_scaling.stub_responses(:describe_auto_scaling_instances, {
          auto_scaling_instances: 10.times.map do |i|
            {
              instance_id: "i-#{1239013 + i}",
              availability_zone: 'us-east-2',
              lifecycle_state: 'InService',
              health_status: 'GOOD',
              launch_configuration_name: launch_configuration.launch_configuration_name.to_s
            }
          end
        })
        subject.length.should == 10
        subject.should be_all { |inst| inst.launch_configuration == launch_configuration }
        subject.should be_all { |inst| inst.availability_zone == 'us-east-2' }
      end
    end
  end

  describe '.description' do
    subject { described_class.all.first }

    it 'returns additional information about the instance' do
      Aerosol::AWS.auto_scaling.stub_responses(:describe_auto_scaling_instances, {
        auto_scaling_instances: [
          {
            instance_id: 'i-1239013',
            availability_zone: 'us-east-2',
            lifecycle_state: 'InService',
            health_status: 'GOOD',
            launch_configuration_name: launch_configuration.launch_configuration_name.to_s
          }
        ]
      })
      Aerosol::AWS.compute.stub_responses(:describe_instances, {
        reservations: [{
          instances: [{
            instance_id: 'i-1239013',
            image_id: launch_configuration.image_id,
            instance_type: launch_configuration.instance_type,
            public_dns_name: 'ec2-dns.aws.amazon.com',
            private_ip_address: '10.0.0.1',
            state: {
              code: 99,
              name: 'running'
            }
          }]
        }]
      })
      subject.image_id.should == launch_configuration.image_id
      subject.description[:instance_type].should == launch_configuration.instance_type
    end

    its(:public_hostname) { should_not be_nil }
    its(:private_ip_address) { should_not be_nil }
  end
end
