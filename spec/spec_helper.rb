$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'rspec'
require 'slugger_deploys'
# Requires supporting files with custom matchers and macros, etc, in ./support/
# and its subdirectories.
#Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

Fog.mock!

SluggerDeploys::AWS.aws_access_key_id = 'MOCK_KEY'
SluggerDeploys::AWS.aws_secret_access_key = 'MOCK_SECRET'
Dockly::Util::Logger.disable! unless ENV['ENABLE_LOGGER'] == 'true'

RSpec.configure do |config|
  config.mock_with :rspec
  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.tty = true
end
