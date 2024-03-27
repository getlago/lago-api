# frozen_string_literal: true

class SlimHelper
  def self.render(path, context)
    Slim::Template.new do
      File.read(
        Rails.root.join("app/views/#{path}.slim"),
        encoding: "UTF-8"
      )
    end.render(context)
  end
end
