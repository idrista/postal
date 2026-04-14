# frozen_string_literal: true

class CreateReplyBridgeAliases < ActiveRecord::Migration[7.0]

  def change
    add_column :servers, :reply_bridge_mode, :string, default: "Off"
    add_column :servers, :reply_bridge_domain, :string
    add_column :servers, :reply_bridge_sender, :string
    add_column :servers, :reply_bridge_alias_ttl_days, :integer, default: 365
    add_column :servers, :reply_bridge_checked_at, :datetime
    add_column :servers, :reply_bridge_mx_status, :string
    add_column :servers, :reply_bridge_mx_error, :string
    add_column :servers, :reply_bridge_sender_status, :string
    add_column :servers, :reply_bridge_sender_error, :string

    create_table :reply_bridge_aliases, id: :integer do |t|
      t.integer :server_id
      t.string :email
      t.string :token
      t.datetime :last_used_at
      t.datetime :expires_at
      t.timestamps
    end

    add_index :reply_bridge_aliases, [:server_id, :email], unique: true
    add_index :reply_bridge_aliases, :token, unique: true
    add_index :reply_bridge_aliases, :server_id
  end

end
