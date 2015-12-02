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
  desc "Verify an aerosol.rb file exists"
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
      desc "Prints out ssh command to all instances of the latest deploy of #{inst.name}"
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

  namespace :env do
    Aerosol.envs.values.each do |env|
      namespace env.name do
        desc "Assumes a role if necessary for #{env.name}"
        task :assume_role => 'aerosol:load' do |name|
          Thread.current[:rake_task] = name
          env.perform_role_assumption
        end

        desc "Run all of the deploys for #{env.name} in parallel"
        multitask :run => env.deploy.map { |dep| "aerosol:#{dep.name}:all" }
      end

      task env.name => ["aerosol:env:#{env.name}:assume_role", "aerosol:env:#{env.name}:run"]
    end
  end


  Aerosol.deploys.values.each do |inst|
    namespace :"#{inst.name}" do
      desc "Assumes a role if necessary"
      task :assume_role => 'aerosol:load' do |name|
        Thread.current[:rake_task] = name
        inst.perform_role_assumption
      end

      desc "Runs the ActiveRecord migration through the SSH connection given"
      task :run_migration => "aerosol:#{inst.name}:assume_role" do |name|
        Thread.current[:rake_task] = name
        Aerosol::Runner.new.with_deploy(inst.name) do |runner|
          runner.run_migration
        end
      end

      desc "Creates a new auto scaling group for the current git hash"
      task :create_auto_scaling_group => "aerosol:auto_scaling:#{inst.auto_scaling.name}"

      desc "Waits for instances of the new autoscaling groups to start up"
      task :wait_for_new_instances => "aerosol:#{inst.name}:assume_role" do |name|
        Thread.current[:rake_task] = name
        Aerosol::Runner.new.with_deploy(inst.name) do |runner|
          runner.wait_for_new_instances
        end
      end

      desc "Runs command to shut down the application on the old instances instead of just terminating"
      task :stop_old_app => "aerosol:#{inst.name}:assume_role" do |name|
        Thread.current[:rake_task] = name
        Aerosol::Runner.new.with_deploy(inst.name) do |runner|
          runner.stop_app
        end
      end

      desc "Terminates instances with the current tag and different git hash"
      task :destroy_old_auto_scaling_groups => "aerosol:#{inst.name}:assume_role" do |name|
        Thread.current[:rake_task] = name
        Aerosol::Runner.new.with_deploy(inst.name) do |runner|
          runner.destroy_old_auto_scaling_groups
        end
      end

      desc "Terminates instances with the current tag and current git hash"
      task :destroy_new_auto_scaling_groups => "aerosol:#{inst.name}:assume_role" do |name|
        Thread.current[:rake_task] = name
        Aerosol::Runner.new.with_deploy(inst.name) do |runner|
          runner.destroy_new_auto_scaling_groups
        end
      end

      desc "Runs a post deploy command"
      task :run_post_deploy => "aerosol:#{inst.name}:assume_role" do |name|
        Thread.current[:rake_task] = name
        inst.run_post_deploy
      end

      ##

      desc "Runs migration and creates auto scaling groups"
      task :all_prep => [:run_migration, :create_auto_scaling_group]

      desc "Waits for new instances, stops old application, destroys old auto scaling groups "\
           "and runs the post deploy command"
      task :all_release => [:wait_for_new_instances, :stop_old_app, :destroy_old_auto_scaling_groups, :run_post_deploy]

      desc "Run migration, create auto scaling group, wait for instances, stop old application, "\
           "destroy old auto scaling groups and run the post deploy command"
      task :all => [:all_prep, :all_release]
      all_deploy_tasks << "aerosol:#{inst.name}:all"

      ##

      desc "Runs migration and creates auto scaling groups in parallel"
      multitask :all_asynch_prep => [:run_migration, :create_auto_scaling_group]

      desc "Same as `all` but runs the migration and creates auto scaling groups in parallel"
      task :all_asynch => [:all_asynch_prep, :all_release]
      all_asynch_deploy_tasks << "aerosol:#{inst.name}:all_asynch"
    end
  end

  desc "Runs all the all deploy tasks in the aerosol.rb"
  task :deploy_all => all_deploy_tasks

  desc "Runs all the all deploy tasks in the aerosol.rb in parallel"
  multitask :deploy_all_asynch => all_asynch_deploy_tasks
end
