require 'fog'
require 'dockly/util'

module SluggerDeploys
end

require 'slugger_deploys/aws'
require 'slugger_deploys/util'
require 'slugger_deploys/aws_model'
require 'slugger_deploys/launch_configuration'
require 'slugger_deploys/auto_scaling'
require 'slugger_deploys/instance'
require 'slugger_deploys/connection'
require 'slugger_deploys/deploy'

module SluggerDeploys
  attr_reader :deploy, :instance, :git_sha
  attr_writer :load_file

  LOAD_FILE = 'deploys.rb'

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

  def setup(file = 'deploys.rb')
    {
      :auto_scalings => SluggerDeploys::AutoScaling.instances,
      :deploys => SluggerDeploys::Deploy.instances,
      :launch_configurations => SluggerDeploys::LaunchConfiguration.instances,
      :sshs => SluggerDeploys::Connection.instances
    }
  end

  {
    :auto_scaling => SluggerDeploys::AutoScaling,
    :deploy => SluggerDeploys::Deploy,
    :launch_configuration => SluggerDeploys::LaunchConfiguration,
    :ssh => SluggerDeploys::Connection
  }.each do |method, klass|
    define_method(method) do |sym, &block|
      if block.nil?
        inst[:"#{method}s"][sym]
      else
        klass.new!(:name => sym, &block)
      end
    end
  end

  [:auto_scalings, :deploys, :launch_configurations, :sshs].each do |method|
    define_method(method) do
      inst[method]
    end
  end

  module_function :inst, :load_inst, :setup, :load_file, :load_file=,
                  :auto_scaling,  :launch_configuration,  :deploy,  :ssh, :git_sha,
                  :auto_scalings, :launch_configurations, :deploys, :sshs
end

require 'slugger_deploys/runner'
require 'slugger_deploys/rake_task'
