# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataExportPart, type: :model do
  it { is_expected.to belong_to(:data_export) }
end
