class SluggerDeploys::Instance
  include SluggerDeploys::AWSModel

  aws_attribute :availability_zone => 'AvailabilityZone',
                :health_status     => 'HealthStatus',
                :id                => 'InstanceId',
                :lifecycle_state   => 'LifecycleState'
  aws_class_attribute :launch_configuration, SluggerDeploys::LaunchConfiguration
  primary_key :id

  def live?
    describe_again
    !!public_hostname
  end

  def public_hostname
    description['dnsName']
  end

  def ami
    description['imageId']
  end

  def description
    @description ||= describe!
  end

  def self.request_all
    SluggerDeploys::AWS.auto_scaling
                .describe_auto_scaling_instances
                .body
                .[]('DescribeAutoScalingInstancesResult')
                .[]('AutoScalingInstances')
  end

private
  def describe!
    ensure_present! :id
    result = SluggerDeploys::AWS.compute.describe_instances('instance-id' => id).body
    result['reservationSet'].first['instancesSet'].first rescue nil
  end

  def describe_again
    @description = nil
    description
  end
end
