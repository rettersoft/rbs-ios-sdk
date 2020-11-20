# RBS

[![CI Status](https://img.shields.io/travis/baranbaygan/RBS.svg?style=flat)](https://travis-ci.org/baranbaygan/RBS)
[![Version](https://img.shields.io/cocoapods/v/RBS.svg?style=flat)](https://cocoapods.org/pods/RBS)
[![License](https://img.shields.io/cocoapods/l/RBS.svg?style=flat)](https://cocoapods.org/pods/RBS)
[![Platform](https://img.shields.io/cocoapods/p/RBS.svg?style=flat)](https://cocoapods.org/pods/RBS)

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Requirements

## Installation

RBS is available through [CocoaPods](https://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'RBS'
```

## Initialize SDK

Initialize the SDK with a user type defined in your project configuration and your project id created in RBS console.

```swift
let rbs = RBS(clientType: .user(userType: "rbs.user.some_user_type"), projectId: "YOUR PROJECT ID")
```



## Authenticate 

RBS client's authenticateWithCustomToken method should be used to authenticate a user. If you don't call this method, client will send actions as an anonymous user.

```swift
rbs.authenticateWithCustomToken(testCustomToken)
```

You can sign out with .signout method.

```swift
rbs.signOut()
```

## RBS Delegate

You can attach a delegate to RBS client.

```swift
rbs.delegate = self
```

And start receiving authentication state changes.

```swift
extension ViewController : RBSClientDelegate {
    func rbsClient(client: RBS, authStatusChanged toStatus: RBSClientAuthStatus) {
        print("RBS authStatusChanged to \(toStatus)")
    }
}
```

## Send Actions

You can use send method to send actions commands to RBS services. The list of which actions will trigger which services is listed in your RBS project configuration.


```swift
rbs.send(action: "rbs.oms.request.SOME_ACTION",
         data: [
            "key": "value",
         ],
         onSuccess: { result in
            print("Result: \(result)")
         },
         onError: { error in
            print("Error Result: \(error)")
         })
```

## Author

baranbaygan, baran@rettermobile.com

## License

RBS is available under the MIT license. See the LICENSE file for more info.
