# This module holds the connections for all AWS services used by the gem.
module Aerosol::AWS
  extend self

  def service(name, klass)
    define_method name do
      if val = instance_variable_get(:"@#{name}")
        val
      else
        instance = klass.new(creds)
        instance_variable_set(:"@#{name}", instance)
      end
    end
    services << name
  end

  def services
    @services ||= []
  end

  def env_attr(*names)
    names.each do |name|
      define_method name do
        instance_variable_get(:"@#{name}") || ENV[name.to_s.upcase]
      end

      define_method :"#{name}=" do |val|
        reset_cache!
        instance_variable_set(:"@#{name}", val)
      end

      env_attrs << name
    end
  end

  def env_attrs
    @env_attrs ||= []
  end

  def creds
    Hash[env_attrs.map { |attr| [attr, public_send(attr)] }].reject { |k, v| v.nil? }
  end

  def reset_cache!
    services.each { |service| instance_variable_set(:"@#{service}", nil) }
  end

  service :sts, Aws::STS::Client
  service :s3, Aws::S3::Client
  service :compute, Aws::EC2::Client
  service :auto_scaling, Aws::AutoScaling::Client
  env_attr :credentials, :stub_responses
end
