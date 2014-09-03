# An environment is a set of deploys.
class Aerosol::Env
  include Dockly::Util::DSL

  dsl_class_attribute :deploy, Aerosol::Deploy, type: Array
end
