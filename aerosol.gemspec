# -*- encoding: utf-8 -*-
require File.expand_path('../lib/aerosol/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Swipely, Inc."]
  gem.email         = %w{tomhulihan@swipely.com bright@swipely.com toddlunter@swipely.com}
  gem.description   = %q{Instance-based deploys made easy}
  gem.summary       = %q{Instance-based deploys made easy}
  gem.homepage      = "https://github.com/upserve/aerosol"
  gem.license       = 'MIT'

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "aerosol"
  gem.require_paths = %w{lib}
  gem.version       = Aerosol::VERSION
  gem.add_dependency 'activerecord', '>= 3.2.0'
  gem.add_dependency 'clamp', '~> 1'
  gem.add_dependency 'excon'
  gem.add_dependency 'aws-sdk-core', '~> 3'
  gem.add_dependency 'aws-sdk-s3', '~> 1'
  gem.add_dependency 'aws-sdk-ec2', '~> 1'
  gem.add_dependency 'aws-sdk-autoscaling', '~> 1'
  gem.add_dependency 'minigit', '~> 0.0.4'
  gem.add_dependency 'net-ssh'
  gem.add_dependency 'net-ssh-gateway'
  gem.add_dependency 'dockly-util', '~> 0.1.0'
  gem.add_development_dependency 'cane'
  gem.add_development_dependency 'pry'
  gem.add_development_dependency 'rake', '~> 10.0'
  gem.add_development_dependency 'rspec', '~> 3'
  gem.add_development_dependency 'webmock'
  gem.add_development_dependency 'vcr'
end
