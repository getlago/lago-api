# frozen_string_literal: true

class DataExportPart < ApplicationRecord
  belongs_to :data_export

  scope :completed, -> { where(completed: true) }
end

# == Schema Information
#
# Table name: data_export_parts
#
#  id             :uuid             not null, primary key
#  completed      :boolean          default(FALSE), not null
#  csv_lines      :text
#  index          :integer
#  object_ids     :uuid             not null, is an Array
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  data_export_id :uuid             not null
#
# Indexes
#
#  index_data_export_parts_on_data_export_id  (data_export_id)
#
# Foreign Keys
#
#  fk_rails_...  (data_export_id => data_exports.id)
#
