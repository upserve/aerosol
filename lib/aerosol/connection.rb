require 'net/ssh'
require 'net/ssh/gateway'

class Aerosol::Connection
  include Dockly::Util::DSL
  include Dockly::Util::Logger::Mixin

  logger_prefix '[aerosol connection]'
  dsl_attribute :user, :host, :jump, :use_private_ip
  default_value :use_private_ip, false

  def with_connection(&block)
    ensure_present! :user, :host

    unless host.is_a? String
      host = :use_private_ip ? host.private_ip_address : host.public_hostname
    end

    if jump
      info "connecting to gateway #{jump[:user] || user}@#{jump[:host]}"
      gateway = Net::SSH::Gateway.new(jump[:host], jump[:user] || user, :forward_agent => true)
      begin
        info "connecting to #{user}@#{host} through gateway"
        gateway.ssh(host, user, &block)
      ensure
        info "shutting down gateway connection"
        gateway.shutdown!
      end
    else
      info "connecting to #{user}@#{host}"
      Net::SSH.start(host, user, &block)
    end
  end
end
