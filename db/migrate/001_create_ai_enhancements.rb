# frozen_string_literal: true
class CreateAiEnhancements < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_enhancements do |table|
      table.bigint :issue_id, null: false
      table.bigint :user_id, null: false
      table.string :mode, null: false
      table.string :state, null: false, default: 'queued'
      table.string :baseline, null: false
      table.text :payload, null: false
      table.integer :lock_version, null: false, default: 0
      table.timestamps
    end
    add_index :ai_enhancements, [:issue_id, :user_id, :created_at], name: 'index_ai_enhancements_owner'
    add_foreign_key :ai_enhancements, :issues, on_delete: :cascade
    add_foreign_key :ai_enhancements, :users, on_delete: :cascade
  end
end
