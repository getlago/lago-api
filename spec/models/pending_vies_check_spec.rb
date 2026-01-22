# frozen_string_literal: true

require "rails_helper"

RSpec.describe PendingViesCheck, type: :model do
  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:billing_entity) }
  it { is_expected.to belong_to(:customer) }
end
