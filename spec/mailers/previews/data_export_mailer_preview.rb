class DataExportMailerPreview < BasePreviewMailer
  def completed
    data_export = FactoryBot.create :data_export, :completed
    DataExportMailer.with(data_export:).completed
  end
end
