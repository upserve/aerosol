# Copyright Swipely, Inc.  All rights reserved.

require 'spec_helper'

describe SluggerDeploys do
  subject { SluggerDeploys }

  {
    :auto_scaling => SluggerDeploys::AutoScaling,
    :deploy => SluggerDeploys::Deploy,
    :launch_configuration => SluggerDeploys::LaunchConfiguration,
    :ssh => SluggerDeploys::Connection
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
