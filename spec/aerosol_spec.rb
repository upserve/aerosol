# Copyright Swipely, Inc.  All rights reserved.

require 'spec_helper'

describe Aerosol do
  subject { Aerosol }

  {
    :auto_scaling => Aerosol::AutoScaling,
    :deploy => Aerosol::Deploy,
    :launch_configuration => Aerosol::LaunchConfiguration,
    :ssh => Aerosol::Connection
  }.each do |name, klass|
    describe ".#{name}" do
      before { subject.send(name, :"runner_test_#{name}") { } }

      it "creates a new #{klass}" do
        klass.instances.keys.should include :"runner_test_#{name}"
      end

      it "accessible via #{klass} without a block " do
        subject.send("#{name}s").keys.should include :"runner_test_#{name}"
      end
    end
  end

  it { should be_an_instance_of(Module) }
end
