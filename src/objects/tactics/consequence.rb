require_relative '../base_object'

class Precondition < BaseObject

  # define the data that goes in this object
  Members = [
    { name: "consequence", type: String },
    { name: "params",      type: Params },
  ]

end
