require 'rubygems'
require 'mechanize'
require 'json'
require 'haml'

MY_EMAIL = ''
MY_PASSWORD = ''

def get_friends_list_from_page page_body
  friends_json_match = page_body.match(/^\s+var friendsData = (\{.+\});$/)
 
  return {} if friends_json_match.nil?

  friends_json = friends_json_match[1].gsub("'","\"").gsub(/(\d+):/,"\"$1\":").gsub(/[\x00-\x19]/," ")

  begin
    JSON.parse friends_json
  rescue JSON::ParserError
    puts 'JSON parsing error. Offending line stored into parse_error.json'
    File.open('parse_error.json','w') {|f| f.write friends_json}
    {}
  end
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


agent = WWW::Mechanize.new
page = agent.get('http://vkontakte.ru')
login_form = page.form('login')
login_form.email = MY_EMAIL
login_form.pass = MY_PASSWORD

#login & redirect
agent.submit( agent.submit(login_form, login_form.buttons.first).forms.first ) 

names = {}
my_friends = []
people = {}

my_friends_list = get_friends_list_from_page agent.get('http://vkontakte.ru/friends.php').body

my_friends_list['friends'].each do |friend|
  my_friends << friend[0]
  names[friend[0]] = friend[1]
end

left = my_friends.length

my_friends.each do |friend_id, friend_name|
  puts left
  left -= 1

  his_friends_list = get_friends_list_from_page agent.get("http://vkontakte.ru/friends.php?id=#{friend_id}").body

  next if his_friends_list['friends'].nil? 

  his_friends_list['friends'].each do |his_friend|
    #mark his friend
    names[his_friend[0]] = his_friend[1]
    people[his_friend[0]] ||= []
    people[his_friend[0]] << friend_id
  end
end

people = people.reject{|id,friends| my_friends.include?(id) || (friends.length < 2)}.sort {|a,b| b[1].length <=> a[1].length}

File.open('friends.html','w') { |f| f.write Haml::Engine.new(page_template).render(Object.new, :people => people, :names => names) }
