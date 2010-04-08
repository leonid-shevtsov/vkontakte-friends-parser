$KCODE = 'u'

require 'rubygems'
require 'sinatra'
require 'sequel'
require 'haml'
require 'mini_magick'
require 'active_support'
require 'vkontakte_grabber.rb'

DB = Sequel.mysql('vkontakte', :username => 'root', :password => 'root')

helpers do
  def protected!
    unless authorized?
      response['WWW-Authenticate'] = %(Basic realm="Vkontakte email and password please.")
      response['Content-Type'] = %(text/html; charset=utf8)
      throw(:halt, [401, "Not authorized\n"])
    end
  end

  def authorized?
    @auth ||=  Rack::Auth::Basic::Request.new(request.env)
    return false unless @auth.provided? && @auth.basic? && @auth.credentials

    begin
      @grabber = VkontakteGrabber.new(@auth.credentials[0], @auth.credentials[1])
      @my_friends = get_my_friends
    rescue
      return false
    end
  end

  def get_friends_for(user_id)

    raw_friends = @grabber.get_friends(user_id)
    return nil if raw_friends['friends'].nil? 

    if user_id.nil?
      user_id = raw_friends['id'].to_i
      @my_id = user_id
    end

    raw_friends['friends'].map do |friend|
      friend_id = friend[0].to_s.strip.to_i
      name = friend[1].to_s.strip
      avatar = friend[2].to_s.strip

      unless DB[:users].where(:id => friend_id).count > 0
        DB[:users].insert(:id => friend_id, :name => name, :avatar => avatar, :updated_at => 2.days.ago)
      end

      friend_id
    end
  end

  def write_friends_to_db(user_id, friend_ids)
    DB[:friends].where(['first_user_id=? or second_user_id=?',user_id, user_id]).delete
    DB[:friends].multi_insert(friend_ids.map{|id| {'first_user_id' => user_id, 'second_user_id' => id}})
  end

  def get_my_friends
    friend_ids = get_friends_for(nil)
    write_friends_to_db(@my_id, friend_ids)
    friend_ids 
  end

  def get_users_friends(user_id)
    user_id = user_id.to_i
    user_record = DB[:users].where(:id => user_id).first

    if user_record 
      if user_record[:updated_at] > 1.day.ago
        # user is cached. get his friends from DB
        friend_ids = DB[:friends].where(:first_user_id => user_id).map{|r| r[:second_user_id]} + DB[:friends].where(:second_user_id => user_id).map{|r| r[:first_user_id]}
      else
        # reload this user
        if friend_ids = get_friends_for(user_id)
          #if we could get his friends
          DB[:users].where(:id => user_id).update(:updated_at => Time.now)
          write_friends_to_db(user_id, friend_ids)
        end
      end
    else
      friend_ids = get_friends_for(user_id)
      DB[:users].insert(:id => user_id, :updated_at => friend_ids ? Time.now : 1.day.ago)
      write_friends_to_db(user_id, friend_ids) if friend_ids
    end

    friend_ids 
  end
end

get '/' do
  haml :index
end

get '/second_circle' do
  protected!

  @people = {}

  @my_friends.each_with_index do |friend_id,i|
    puts i
    his_friends = get_users_friends(friend_id)
    if his_friends
      his_friends.each do |his_friend_id|
        @people[his_friend_id] ||= []
        @people[his_friend_id] << friend_id
      end
    end
  end

  @my_friends << @my_id # so i don't show up in 2nd circle

  @people = @people.reject{|id,friends| @my_friends.include?(id) || (friends.length < 4)}.sort {|a,b| b[1].length <=> a[1].length}
  @names ||= {}
  @avatars ||= {}

  DB[:users].where(:id => @people.map{|a| a[0]}+@my_friends).each do |row|
    @names[row[:id].to_i] = row[:name]
    @avatars[row[:id].to_i] = row[:avatar]
  end

  haml :second_circle
end

