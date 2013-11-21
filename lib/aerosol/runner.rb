require 'socket'
require 'active_record'
require 'grit'

class Aerosol::Runner
  extend Dockly::Util::Delegate
  include Dockly::Util::Logger::Mixin

  logger_prefix '[aerosol runner]'
  attr_reader :deploy

  def run_migration
    require_deploy!
    return unless deploy.migrate?
    raise 'To run a migration, $RAILS_ENV must be set.' if ENV['RAILS_ENV'].nil?

    info "running migration"
    begin
      info "loading config for env #{ENV['RAILS_ENV']}"
      original_config = YAML.load(ERB.new(File.read(db_config_path)).result)[ENV['RAILS_ENV']]
      debug "creating ssh tunnel"
      migration_ssh.with_connection do |session|
        # session.logger.sev_threshold=Logger::Severity::DEBUG
        debug "finding free port"
        port = random_open_port
        db_port = original_config['port'] || 3306 # TODO: get default port from DB driver
        host = original_config['host']
        info "forwarding 127.0.0.1:#{port} --> #{host}:#{db_port}"
        session.forward.local(port, host, db_port)
        child = fork do
          with_prefix('child:') do |logger|
            logger.debug "establishing connection"
            ActiveRecord::Base.establish_connection(original_config.merge(
                                                      'host' => '127.0.0.1',
                                                      'port' => port
                                                    ))
            logger.info "running migration"
            ActiveRecord::Migrator.migrate(%w[db/migrate])
          end
        end
        debug "waiting for child"
        exitstatus = nil
        session.loop(0.1) do
          pid = Process.waitpid(child, Process::WNOHANG)
          exitstatus = $?.exitstatus if !pid.nil?
          pid.nil?
        end
        raise "migration failed: #{exitstatus}" unless exitstatus == 0
      end
      info "complete"
    ensure
      ActiveRecord::Base.clear_all_connections!
    end
    info "migration ran"
  end

  def wait_for_new_instances
    require_deploy!
    info "waiting for new instances"
    start_time = Time.now
    remaining_instances = new_instances
    while !remaining_instances.empty? && (Time.now < (start_time + instance_live_grace_period))
      info "waiting for instances to be live (#{remaining_instances.count} remaining)"
      remaining_instances.reject! { |instance| healthy?(instance) }
      sleep(10) unless remaining_instances.empty?
    end
    unless remaining_instances.empty?
      raise "[aerosol runner] site live check timed out after #{instance_live_grace_period} seconds"
    end
    info "new instances are up"
  end

  def healthy?(instance)
    return false unless instance.live?

    ssh.host(instance.public_hostname)
    success = false
    ssh.with_connection do |session|
      ret = ssh_exec!(session, "wget -q 'http://localhost:#{app_port}#{live_check}' -O /dev/null")
      success = ret[:exit_status].zero?
    end
    success
  rescue
    false
  end

  def stop_app
    info "stopping old app"
    to_stop = old_instances

    info "starting with #{to_stop.length} instances to stop"

    stop_app_retries.succ.times do |n|
      break if to_stop.empty?
      debug "stop app: #{to_stop.length} instances remaining"
      to_stop.reject! { |instance| stop_one_app(instance) }
    end

    if to_stop.length.zero?
      info "successfully stopped the app on each old instance"
    elsif !continue_if_stop_app_fails
      raise "Failed to stop app on #{to_stop.length} instances"
    end
    info "stopped old app"
  end

  def destroy_old_auto_scaling_groups
    require_deploy!
    info "destroying old autoscaling groups"
    sleep deploy.sleep_before_termination
    old_auto_scaling_groups.map(&:destroy)
    info "destroyed old autoscaling groups"
  end

  def old_instances
    require_deploy!
    old_auto_scaling_groups.map(&:launch_configuration).compact.map(&:all_instances).flatten.compact
  end

  def old_auto_scaling_groups
    require_deploy!
    Aerosol::LaunchConfiguration.all # load all of the launch configurations first
    Aerosol::AutoScaling.all.select { |asg|
      (asg.tags['Deploy'].to_s == auto_scaling.tags['Deploy']) &&
        (asg.tags['GitSha'] != auto_scaling.tags['GitSha'])
    }
  end

  def new_instances
    require_deploy!
    start_time = Time.now
    while launch_configuration.all_instances.length < auto_scaling.min_size \
        && (Time.now < (start_time + instance_live_grace_period))
      info "Waiting for instances to come up"
      sleep 10
    end
    launch_configuration.all_instances
  end

  def with_deploy(name)
    unless dep = Aerosol::Deploy[name]
      raise "No deploy named '#{name}'"
    end
    original = @deploy
    @deploy = dep
    yield self
    @deploy = original
  end

  def require_deploy!
    raise "@deploy must be present" if deploy.nil?
  end

  def git_sha
    @git_sha ||= Aerosol::Util.git_sha
  end

  delegate :ssh, :migration_ssh, :package, :auto_scaling, :stop_command,
           :live_check, :db_config_path, :instance_live_grace_period,
           :app_port, :continue_if_stop_app_fails, :stop_app_retries, :to => :deploy
  delegate :launch_configuration, :to => :auto_scaling

private

  def stop_one_app(instance)
    debug "attempting to stop app on: #{instance.public_hostname}"
    ssh.host(instance.public_hostname)
    ssh.with_connection do |session|
      session.exec!(stop_command)
      session.loop
    end
    info "successfully stopped app on: #{instance.public_hostname}"
    true
  rescue => ex
    warn "stop app failed on #{instance.public_hostname} due to: #{ex}"
    false
  end

  # inspired by: http://stackoverflow.com/questions/3386233/how-to-get-exit-status-with-rubys-netssh-library
  def ssh_exec!(ssh, command, options = {})
    res = { :out => "", :err => "", :exit_status => nil }
    ssh.open_channel do |channel|
      if options[:tty]
        channel.request_pty do |ch, success|
          raise "could not start a pseudo-tty" unless success
          channel = ch
        end
      end

      channel.exec(command) do |ch, success|
        raise "unable to run remote cmd: #{command}" unless success

        channel.on_data { |_, data| res[:out] << data }
        channel.on_extended_data { |_, type, data| res[:err] << data }
        channel.on_request("exit-status") { |_, data| res[:exit_status] = data.read_long }
      end
    end
    ssh.loop
    res
  end

  def random_open_port
    socket = Socket.new(:INET, :STREAM, 0)
    socket.bind(Addrinfo.tcp("127.0.0.1", 0))
    port = socket.local_address.ip_port
    socket.close
    port
  end
end
