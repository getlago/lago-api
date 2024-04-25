# frozen_string_literal: true

require_relative 'ruby_sandbox/runner'

module LagoUtils
  module RubySandbox
    def self.run(code)
      LagoUtils::RubySandbox::Runner.new(code).run
    end
  end
end
