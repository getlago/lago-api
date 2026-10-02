# frozen_string_literal: true

# The single definition of the runner's error hierarchy. Required first by every other
# file, so no module needs to guard against defining these twice.
module BillingMatrix
  class Error < StandardError; end

  # A row is malformed. The message must name the row id, its source file, and the
  # offending field — a validation error nobody can locate is a validation error nobody
  # fixes.
  class InvalidRow < Error; end

  # The row asks for something the harness cannot do. This is a first-class outcome, not
  # a failure: it means the row is ahead of the runner. It records as :errored and never
  # as :passed, because a step that did not run must never read as green.
  class Unsupported < Error; end
end
