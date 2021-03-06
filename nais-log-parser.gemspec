# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "nais/log/parser/version"

Gem::Specification.new do |spec|
  spec.name          = "nais-log-parser"
  spec.version       = Nais::Log::Parser::VERSION
  spec.authors       = ["Terje Sannum"]
  spec.email         = ["terje.sannum@nav.no"]

  spec.summary       = %q{Log parsing}
  spec.homepage      = "https://github.com/nais/nais-log-parser"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency 'logfmt', '= 0.0.9'

  spec.required_ruby_version = '>= 2.3.0'
  spec.add_development_dependency "rspec", "~> 3.0"

  spec.metadata    = {
    'github_repo' => 'ssh://github.com/nais/nais-log-parser'
  }
end
