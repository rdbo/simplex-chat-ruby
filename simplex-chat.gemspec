# frozen_string_literal: true

require_relative "lib/simplex-chat/version"

Gem::Specification.new do |spec|
  # Package info
  spec.name = "simplex-chat"
  spec.version = SimpleXChat::VERSION
  spec.authors = ["rdbo"]
  spec.email = ["rdbodev@gmail.com"]

  spec.summary = "SimpleX Chat API"
  spec.description = "SimpleX Chat client API implementation for Ruby"
  spec.homepage = "https://github.com/rdbo/simplex-chat-ruby"
  spec.license = "AGPL-3.0-only"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile] ||
        f.end_with?("png"))
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Dependencies
  spec.add_dependency "websocket", "~> 1.2"
  spec.add_dependency "concurrent-ruby", "~> 1.3"
end
