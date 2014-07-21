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
        expect(klass.instances.keys).to include(:"runner_test_#{name}")
      end

      it "accessible via #{klass} without a block " do
        expect(subject.send("#{name}s").keys).to include(:"runner_test_#{name}")
      end
    end
  end

  it { should be_an_instance_of(Module) }

  describe ".namespace" do
    let(:namespace) { "test" }
    before { subject.namespace namespace }

    it "sets the namespace" do
      expect(subject.instance_variable_get(:"@namespace")).to eq(namespace)
    end

    it "returns the namespace after being set" do
      expect(subject.namespace).to eq(namespace)
    end
  end
end
