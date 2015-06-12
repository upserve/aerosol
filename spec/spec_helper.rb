$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'rspec'
require 'pry'
require 'aerosol'
# Requires supporting files with custom matchers and macros, etc, in ./support/
# and its subdirectories.
#Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

Aerosol::AWS.credentials = Aws::Credentials.new('MOCK_KEY', 'MOCK_SECRET')
Aerosol::AWS.stub_responses = true
Dockly::Util::Logger.disable! unless ENV['ENABLE_LOGGER'] == 'true'

RSpec.configure do |config|
  config.mock_with :rspec
  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.tty = true
  config.filter_run_excluding local: true if ENV['CI']
end
