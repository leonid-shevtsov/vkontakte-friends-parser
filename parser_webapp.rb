$KCODE = 'u'

require 'rubygems'
require 'sinatra'
require 'haml'
require 'mini_magick'
require 'active_support'
require 'redis'
require 'run_later.rb'
require 'vkontakte_grabber.rb'

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
      @redis_client = Redis.new(:thread_safe => true)
      @grabber = VkontakteGrabber.new(@auth.credentials[0], @auth.credentials[1])
      @my_friends = get_my_friends
      return !@my_id.blank?
    #rescue
#      return false
    end
  end

  def get_friends_for(user_id)

    raw_friends = @grabber.get_friends(user_id)
    return [] if raw_friends['friends'].nil? 

    if user_id.nil?
      user_id = raw_friends['id'].to_i
      @my_id = user_id
    end

    raw_friends['friends'].map do |friend|
      friend_id = friend[0].to_s.strip.to_i

      @redis_client["name_#{friend_id}"] = friend[1].to_s.strip
      @redis_client["avatar_#{friend_id}"] = friend[2].to_s.strip

      friend_id
    end
  end

  def write_friends_to_db(user_id, friend_ids)
    old_friend_ids = @redis_client.smembers("friends_#{user_id}").map(&:to_i)
    
    (old_friend_ids - friend_ids).each do |friend_id_to_remove|
      @redis_client.srem("friends_#{user_id}", friend_id_to_remove)
      @redis_client.srem("friends_#{friend_id_to_remove}", user_id)
    end

    (friend_ids - old_friend_ids).each do |friend_id_to_add|
      @redis_client.sadd("friends_#{user_id}", friend_id_to_add)
      @redis_client.sadd("friends_#{friend_id_to_add}", user_id)
    end

    @redis_client["friends_updated_at_#{user_id}"] = Time.now.to_i
  end

  def get_my_friends
    friend_ids = get_friends_for(nil)
    write_friends_to_db(@my_id, friend_ids)
    friend_ids 
  end

  def get_users_friends(user_id)
    user_id = user_id.to_i

    if Time.at(@redis_client.get("friends_updated_at_#{user_id}").to_i) < 1.day.ago
      @redis_client.multi do
        friend_ids = get_friends_for(user_id)
        write_friends_to_db(user_id, friend_ids)
      end
    else
      friend_ids = @redis_client.smembers("friends_#{user_id}").map(&:to_i)
    end

    friend_ids 
  end
end

get '/' do
  haml :index
end

get '/second_circle' do
  protected!
  response['Content-Type'] = %(text/html; charset=utf8)

  # check if process finished
  if people_json = @redis_client.get("second_circle_#{@my_id}")
   
    @people = Yajl::Parser.parse(people_json)

    @names ||= {}
    @avatars ||= {}

    (@people.map{|a| a[0]} + @my_friends + [@my_id]).uniq.each do |id|
      @names[id] = @redis_client.get "name_#{id}"
      @avatars[id] = @redis_client.get "avatar_#{id}"
    end
    haml :second_circle
  elsif (remaining_friends = @redis_client.get("remaining_friends_#{@my_id}").to_i) > 0
    "Твои друзья будут обрабатываться ориентировочно еще #{remaining_friends} секунд. Потом обнови эту страницу."
  else
    @redis_client["remaining_friends_#{@my_id}"] = @my_friends.length
    RunLater.run_now = true #TODO 
    run_later do
      people={}
      @my_friends.each do |friend_id|
        his_friends = get_users_friends(friend_id)
        if his_friends
          his_friends.each do |his_friend_id|
            people[his_friend_id] ||= []
            people[his_friend_id] << friend_id
          end
        end
        @redis_client.decr "remaining_friends_#{@my_id}"
      end

      @my_friends << @my_id # so i don't show up in 2nd circle

      people = people.reject{|id,friends| @my_friends.include?(id) || (friends.length < 4)}.sort {|a,b| b[1].length <=> a[1].length}

      @redis_client["second_circle_#{@my_id}"] = Yajl::Encoder.encode(people)
      @redis_client.expire "second_circle_#{@my_id}", 1.day
    end
    #"Обработка запущена. Твои друзья обработаются ориентировочно за #{@my_friends.length} секунд. Потом обнови эту страницу."
    "<meta http-equiv='refresh' content='1'>Обнови страницу."
  end
end

