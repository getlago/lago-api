# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhook, type: :model do
  it { is_expected.to belong_to(:webhook_endpoint) }
  it { is_expected.to belong_to(:object).optional }
end
