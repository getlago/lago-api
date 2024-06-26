# frozen_string_literal: true

if ENV['LAGO_ENABLE_YJIT'] == 'true' && defined? RubyVM::YJIT.enable
  Rails.application.config.after_initialize do
    # Enable YJIT for the entire application
    RubyVM::YJIT.enable
  end
end
