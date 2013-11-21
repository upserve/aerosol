require 'spec_helper'

describe Aerosol::Instance do
  let!(:launch_config) do
    Aerosol::LaunchConfiguration.new! do
      name :launch_config_for_instances
      ami 'ami-123-abc'
      instance_type 'm1.large'
      stub :sleep
    end
  end

  let!(:auto_scaling) do
    Aerosol::AutoScaling.new! do
      name :as_group_for_instances
      availability_zones 'us-east-2'
      launch_configuration :launch_config_for_instances
      min_size 10
      max_size 10
      stub :sleep
    end
  end

  describe '.all' do
    subject { described_class.all }

    context 'when there are no instances' do
      it { should be_empty }
    end

    context 'when there are instances' do
      before { launch_config.create; auto_scaling.create }
      after { launch_config.destroy; auto_scaling.destroy }

      it 'materializes each of them into an object' do
        subject.length.should == 10
        subject.should be_all { |inst| inst.launch_configuration == launch_config }
        subject.should be_all { |inst| inst.availability_zone == 'us-east-2' }
      end
    end
  end

  describe '.description' do
    before { auto_scaling.create }
    after { auto_scaling.destroy }

    subject { described_class.all.first }

    it 'returns additional information about the instance' do
      subject.description['imageId'].should == launch_config.ami
      subject.description['instanceType'].should == launch_config.instance_type
    end

    its(:public_hostname) { should_not be_nil }
  end
end
