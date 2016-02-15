require 'active_support/core_ext/object/blank'

class Aerosol::Instance
  include Aerosol::AWSModel

  aws_attribute :availability_zone, :health_status, :instance_id, :lifecycle_state
  aws_class_attribute :launch_configuration, Aerosol::LaunchConfiguration
  primary_key :instance_id

  def live?
    describe_again
    instance_state_name == 'running'
  end

  def instance_state_name
    description[:state][:name]
  end

  def public_hostname
    description[:public_dns_name]
  end

  def private_ip_address
    description[:private_ip_address]
  end

  def address
    if public_hostname.blank?
      private_ip_address
    else
      public_hostname
    end
  end

  def image_id
    description[:image_id]
  end

  def description
    @description ||= describe!
  end

  def self.request_all_for_token(next_token)
    options = next_token.nil? ? {} : { next_token: next_token }
    Aerosol::AWS.auto_scaling.describe_auto_scaling_instances(options)
  end

  def self.request_all
    next_token = nil
    instances = []

    begin
      new_instances = request_all_for_token(next_token)
      instances.concat(new_instances.auto_scaling_instances)
      next_token = new_instances.next_token
    end until next_token.nil?

    instances
  end

private
  def describe!
    ensure_present! :instance_id
    result = Aerosol::AWS.compute.describe_instances(instance_ids: [instance_id])
    result.reservations.first.instances.first.to_h rescue nil
  end

  def describe_again
    @description = nil
    description
  end
end
