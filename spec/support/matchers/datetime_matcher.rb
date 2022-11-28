# frozen_string_literal: true

RSpec::Matchers.define :match_datetime do |expectation|
  match do |subject|
    subject = subject.to_datetime.change(usec: 0) if subject.is_a?(String)
    expectation = DateTime.parse(expectation) if expectation.is_a?(String)

    subject == expectation.change(usec: 0)
  end
end
