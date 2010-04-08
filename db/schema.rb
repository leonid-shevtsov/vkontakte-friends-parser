require 'rubygems'
require 'sequel'

#db = Sequel.sqlite('db/vkontakte.sqlite3')
db = Sequel.mysql('vkontakte', :username => 'root', :password => 'root')

db.create_table :users do
  primary_key :id
  String :name
  String :avatar
  Time :updated_at
end

db.create_table :friends do
  foreign_key :first_user_id, :users
  foreign_key :second_user_id, :users
end
