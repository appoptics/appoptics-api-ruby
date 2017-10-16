lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'appoptics/metrics/version'

Gem::Specification.new do |s|
  s.name        = 'appoptics-api-ruby'
  s.version     = '2.1.3'
  s.date        = '2017-10-13'
  s.summary     = "Ruby bindings for the AppOptics API"
  s.description = "An easy to use ruby wrapper for the AppOptics API"
  s.authors     = ["Greg McKeever", "Matt Sanders"]
  s.email       = 'greg@solarwinds.cloud'
  s.files       = ["lib/appoptics/metrics.rb"]
  s.homepage    =
    'https://github.com/AppOptics/appoptics-api-ruby'
  s.license       = 'BSD 3-clause'
  s.require_paths = %w[lib]

## runtime dependencies
  s.add_dependency 'faraday'
  s.add_dependency 'aggregate', '~> 0.2.2'

  s.files = `git ls-files`.split("\n")
  s.test_files = `git ls-files -- {test,spec,features}/*`.split("\n")

  s.cert_chain = ["certs/appoptics-public.pem"]
  if ENV['GEM_SIGNING_KEY']
    s.signing_key = ENV['GEM_SIGNING_KEY']
  end
end
