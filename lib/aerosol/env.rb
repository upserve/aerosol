# An environment is a set of deploys.
class Aerosol::Env
  include Dockly::Util::DSL

  dsl_attribute :assume_role
  dsl_class_attribute :deploy, Aerosol::Deploy, type: Array

  default_value :assume_role, nil

  def perform_role_assumption
    return if assume_role.nil?
    Aws.config.update(
      credentials: Aws::AssumeRoleCredentials.new(
        role_arn: assume_role,
        role_session_name: "aerosol-#{name}",
        client: Aerosol::AWS.sts
      )
    )
  end
end
