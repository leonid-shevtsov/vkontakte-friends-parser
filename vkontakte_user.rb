#require 'vkontakte_client'

# TODO all of this 
class VkontakteUser
  private_class_method :new
 
  attr_reader :id

  def self.find(id)
    #get data
    #call new
    new(id)
  end

  #TODO some personal data

  #TODO Should return an array of VkontakteUser objects
  #TODO what to return if the user has hidden his friends?
  def friends
    #get friends page
    #get json from friends page
    #parse
    []
  end

private
  def initialize(id, attributes={})
    @id = id
  end
end

vk = VkontakteUser.find(10)

puts vk.id
