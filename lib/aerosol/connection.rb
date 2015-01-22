require 'net/ssh'
require 'net/ssh/gateway'

class Aerosol::Connection
  include Dockly::Util::DSL
  include Dockly::Util::Logger::Mixin

  logger_prefix '[aerosol connection]'
  dsl_attribute :user, :host, :jump

  def with_connection(&block)
    ensure_present! :user, :host

    actual_host = host.is_a?(String) ? host : (host.public_hostname || host.private_ip_address)

    if jump
      info "connecting to gateway #{jump[:user] || user}@#{jump[:host]}"
      gateway = nil
      Timeout.timeout(20) do
        gateway = Net::SSH::Gateway.new(jump[:host], jump[:user] || user, :forward_agent => true)
      end

      begin
        info "connecting to #{user}@#{actual_host} through gateway"
        gateway.ssh(actual_host, user, &block)
      ensure
        info "shutting down gateway connection"
        gateway.shutdown!
      end
    else
      info "connecting to #{user}@#{actual_host}"
      Net::SSH.start(actual_host, user, &block)
    end
  rescue Timeout::Error => ex
    error "Timeout error #{ex.message}"
    error ex.backtrace.join("\n")
  end
end
