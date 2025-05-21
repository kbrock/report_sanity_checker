
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "report_sanity_checker/version"

Gem::Specification.new do |spec|
  spec.name          = "report_sanity_checker"
  spec.version       = ReportSanityChecker::VERSION
  spec.authors       = ["Keenan Brock"]
  spec.email         = ["keenan@thebrocks.net"]

  spec.summary       = %q{Quick sanity checking of miq reports}
  spec.description   = %q{Script to outline performance of miq report yml files}
  spec.homepage      = "https://github.com/kbrock/report_sanity_checker"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = %w(report_sanity_checker)
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
#  spec.add_runtime_dependency     "terminal-table"
end
