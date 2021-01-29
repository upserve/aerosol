require 'yaml'
require 'aws-sdk-autoscaling'
require 'aws-sdk-core'
require 'aws-sdk-s3'
require 'aws-sdk-ec2'
require 'dockly/util'
require 'base64'

Aws.config.update({ region: 'us-east-1' }) if Aws.config[:region].nil?

module Aerosol
  require 'aerosol/aws'
  require 'aerosol/util'
  require 'aerosol/aws_model'
  require 'aerosol/launch_configuration'
  require 'aerosol/auto_scaling'
  require 'aerosol/instance'
  require 'aerosol/connection'
  require 'aerosol/deploy'
  require 'aerosol/env'

  attr_reader :deploy, :instance, :git_sha, :namespace
  attr_writer :load_file

  LOAD_FILE = 'aerosol.rb'

  def load_file
    @load_file || LOAD_FILE
  end

  def inst
    @instance ||= load_inst
  end

  def load_inst
    setup.tap do |state|
      if File.exists?(load_file)
        instance_eval(IO.read(load_file), load_file)
      end
    end
  end

  def namespace(value = nil)
    if value.nil?
      @namespace
    else
      @namespace = value
    end
  end

  def region(value = nil)
    if value.nil?
      Aws.config[:region]
    else
      Aws.config.update(region: value)
    end
  end

  def setup
    {
      :auto_scalings => Aerosol::AutoScaling.instances,
      :deploys => Aerosol::Deploy.instances,
      :launch_configurations => Aerosol::LaunchConfiguration.instances,
      :sshs => Aerosol::Connection.instances,
      :envs => Aerosol::Env.instances
    }
  end

  {
    :auto_scaling => Aerosol::AutoScaling,
    :deploy => Aerosol::Deploy,
    :launch_configuration => Aerosol::LaunchConfiguration,
    :ssh => Aerosol::Connection,
    :env => Aerosol::Env
  }.each do |method, klass|
    define_method(method) do |sym, &block|
      if block.nil?
        inst[:"#{method}s"][sym]
      else
        klass.new!(:name => sym, &block)
      end
    end
  end

  [:auto_scalings, :deploys, :launch_configurations, :sshs, :envs].each do |method|
    define_method(method) do
      inst[method]
    end
  end

  module_function :inst, :load_inst, :setup, :load_file, :load_file=,
                  :auto_scaling,  :launch_configuration,  :deploy,  :ssh, :git_sha,
                  :auto_scalings, :launch_configurations, :deploys, :sshs,
                  :namespace, :env, :envs, :region
end

require 'aerosol/runner'
require 'aerosol/rake_task'
