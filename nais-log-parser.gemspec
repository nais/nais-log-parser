# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "nais/log/parser/version"

Gem::Specification.new do |spec|
  spec.name          = "nais-log-parser"
  spec.version       = Nais::Log::Parser::VERSION
  spec.authors       = ["Terje Sannum"]
  spec.email         = ["terje.sannum@nav.no"]

  spec.summary       = %q{Fluentd plugin and functions for parsing logs}
  spec.homepage      = "https://github.com/nais/nais-log-parser"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.15"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
