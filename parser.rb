require 'rubygems'
require 'mechanize'
require 'json'
require 'haml'

require 'vkontakte_grabber.rb'
require 'config.rb'
#MY_EMAIL = ''
#MY_PASSWORD = ''

unless defined?(MY_EMAIL)
  puts 'Look at the source and fill in your credentials'
  exit
end

page_template = <<EOT
!!!
%html
  %body
    %h1="Total people in 2nd circle: \#{people.length}"
    %ul
      -people.each do |id,friends|
        %li
          %div
            %a{ :href=>"http://vkontakte.ru/id\#{id}"}=names[id]
            ="(\#{friends.length})"
          %div
            =friends.map{|id| names[id]}.join ', '
EOT

grabber = VkontakteGrabber.new(MY_EMAIL, MY_PASSWORD)

names = {}
my_friends = []
people = {}

my_friends_list = grabber.get_friends

if my_friends_list == {}
  puts 'Can\'t get your friends list; probably the credentials are all wrong'
  exit
end

my_friends_list['friends'].each do |friend|
  friend_id = friend[0].to_s.strip.to_i
  my_friends << friend_id
  names[friend_id] = friend[1].strip
end

left = my_friends.length

my_friends.each do |friend_id|
  puts left
  left -= 1

  his_friends_list = grabber.get_friends(friend_id)
  sleep 1 # to avoid vkontakte friend blocking

  if his_friends_list['friends'].nil? 
    puts names[friend_id]
    next
  end

  his_friends_list['friends'].each do |his_friend|
    #mark his friend
    his_friend_id = his_friend[0].to_s.strip.to_i
    names[his_friend_id] = his_friend[1].strip
    people[his_friend_id] ||= []
    people[his_friend_id] << friend_id
  end
end

my_id = my_friends_list['id']
my_friends << my_id # so I don't appear in the list of people

people = people.reject{|id,friends| my_friends.include?(id) || (friends.length < 2)}.sort {|a,b| b[1].length <=> a[1].length}

File.open('friends.html','w') { |f| f.write Haml::Engine.new(page_template).render(Object.new, :people => people, :names => names) }

puts 'Look for your list in friends.html'
