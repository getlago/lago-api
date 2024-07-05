# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataExports::ExportResourcesService, type: :service do
  subject(:result) { described_class.call(data_export:) }

  it 'does something'
end
