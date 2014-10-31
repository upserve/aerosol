require 'socket'
require 'active_record'
require 'grit'
require 'timeout'

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
          GC.disable
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

    live_instances = []
    Timeout.timeout(instance_live_grace_period) do
      loop do
        current_instances = new_instances
        remaining_instances = current_instances - live_instances
        info "waiting for instances to be live (#{remaining_instances.count} remaining)"
        debug "current instances: #{current_instances.map(&:id)}"
        debug "live instances: #{live_instances.map(&:id)}"
        live_instances.concat(remaining_instances.select { |instance| healthy?(instance) })
        break if (current_instances - live_instances).empty?
        sleep(10)
      end
    end

    info "new instances are up"
  rescue Timeout::Error
    raise "[aerosol runner] site live check timed out after #{instance_live_grace_period} seconds"
  end

  def healthy?(instance)
    unless instance.live?
      debug "#{instance.id} is not live"
      return false
    end

    ssh.host(instance)
    success = false
    ssh.with_connection do |session|
      success = is_alive?.nil? ? check_site_live(session) : is_alive?.call(session, self)
    end

    if success
      debug "#{instance.id} is healthy"
    else
      debug "#{instance.id} is not healthy"
    end
    success
  rescue => ex
    debug "#{instance.id} is not healthy: #{ex.message}"
    false
  end

  def check_site_live(session)
    command = [
      'wget',
      '-q',
      # Since we're hitting localhost, the cert will always be invalid, so don't try to check it.
      deploy.ssl ? '--no-check-certificate' : nil,
      "'#{deploy.live_check_url}'",
      '-O',
      '/dev/null'
    ].compact.join(' ')

    ret = ssh_exec!(session, command)
    ret[:exit_status].zero?
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

  def destroy_new_auto_scaling_groups
    require_deploy!
    info "destroying autoscaling groups created for this sha"
    new_auto_scaling_groups.map(&:destroy)
    info "destroyed new autoscaling groups"
  end

  def old_instances
    require_deploy!
    old_auto_scaling_groups.map(&:launch_configuration).compact.map(&:all_instances).flatten.compact
  end

  def old_auto_scaling_groups
    select_auto_scaling_groups { |asg| asg.tags['GitSha'] != auto_scaling.tags['GitSha'] }
  end

  def new_auto_scaling_groups
    select_auto_scaling_groups { |asg| asg.tags['GitSha'] == auto_scaling.tags['GitSha'] }
  end

  def select_auto_scaling_groups(&block)
    require_deploy!
    Aerosol::LaunchConfiguration.all # load all of the launch configurations first
    Aerosol::AutoScaling.all.select { |asg|
      (asg.tags['Deploy'].to_s == auto_scaling.tags['Deploy']) &&
        (block.nil? ? true : block.call(asg))
    }
  end

  def new_instances
    require_deploy!
    while launch_configuration.all_instances.length < auto_scaling.min_size
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
           :app_port, :continue_if_stop_app_fails, :stop_app_retries,
           :is_alive?, :to => :deploy
  delegate :launch_configuration, :to => :auto_scaling

private

  def stop_one_app(instance)
    debug "attempting to stop app on: #{instance.public_hostname}"
    ssh.host(instance)
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
