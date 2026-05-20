# frozen_string_literal: true

class EnablePgTrgmExtension < ActiveRecord::Migration[8.0]
  def change
    enable_extension "pg_trgm"
  end
end
