require 'rake'
require 'aerosol'

$rake_task_logger = Dockly::Util::Logger.new('[aerosol rake_task]', STDOUT, false)

class Rake::AutoScalingTask < Rake::Task
  def needed?
    !auto_scaling.exists?
  end

  def auto_scaling
    Aerosol.auto_scaling(name.split(':').last.to_sym)
  end
end

module Rake::DSL
  def auto_scaling(*args, &block)
    Rake::AutoScalingTask.define_task(*args, &block)
  end
end

namespace :aerosol do
  task :load do
    raise "No aerosol.rb found!" unless File.exist?('aerosol.rb')
  end

  namespace :auto_scaling do
    Aerosol.auto_scalings.values.reject(&:from_aws).each do |inst|
      auto_scaling inst.name => 'aerosol:load' do |name|
        Thread.current[:rake_task] = name
        inst.create
      end
    end
  end

  namespace :ssh do
    Aerosol.deploys.values.each do |inst|
      task inst.name do |name|
        Thread.current[:rake_task] = name
        inst.generate_ssh_commands.each do |ssh_command|
          puts ssh_command
        end
      end
    end
  end

  all_deploy_tasks = []
  all_asynch_deploy_tasks = []

  Aerosol.deploys.values.each do |inst|
    namespace :"#{inst.name}" do
      task :run_migration => 'aerosol:load' do |name|
        Thread.current[:rake_task] = name
        Aerosol::Runner.new.with_deploy(inst.name) do |runner|
          runner.run_migration
        end
      end

      task :create_auto_scaling_group => "aerosol:auto_scaling:#{inst.auto_scaling.name}"

      task :wait_for_new_instances => 'aerosol:load' do |name|
        Thread.current[:rake_task] = name
        Aerosol::Runner.new.with_deploy(inst.name) do |runner|
          runner.wait_for_new_instances
        end
      end

      task :stop_old_app => 'aerosol:load' do |name|
        Thread.current[:rake_task] = name
        Aerosol::Runner.new.with_deploy(inst.name) do |runner|
          runner.stop_app
        end
      end

      task :destroy_old_auto_scaling_groups => 'aerosol:load' do |name|
        Thread.current[:rake_task] = name
        Aerosol::Runner.new.with_deploy(inst.name) do |runner|
          runner.destroy_old_auto_scaling_groups
        end
      end

      task :run_post_deploy => 'aerosol:load' do |name|
        Thread.current[:rake_task] = name
        inst.run_post_deploy
      end

      ##

      task :all_prep => [:run_migration, :create_auto_scaling_group]

      task :all_release => [:wait_for_new_instances, :stop_old_app, :destroy_old_auto_scaling_groups, :run_post_deploy]

      task :all => [:all_prep, :all_release]
      all_deploy_tasks << "aerosol:#{inst.name}:all"

      ##

      multitask :all_asynch_prep => [:build_package, :run_migration, :create_auto_scaling_group]

      task :all_asynch => [:all_asynch_prep, :all_release]
      all_asynch_deploy_tasks << "aerosol:#{inst.name}:all_asynch"
    end
  end

  task :deploy_all => all_deploy_tasks
  multitask :deploy_all_asynch => all_asynch_deploy_tasks
end
