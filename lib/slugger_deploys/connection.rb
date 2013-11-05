require 'net/ssh'
require 'net/ssh/gateway'

class SluggerDeploys::Connection
  include Dockly::Util::DSL
  include Dockly::Util::Logger::Mixin

  logger_prefix '[slugger connection]'
  dsl_attribute :user, :host, :jump

  def with_connection(&block)
    ensure_present! :user, :host

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
