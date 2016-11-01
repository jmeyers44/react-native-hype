// RCTHypeMesh.m
#import "HypeMesh.h"
#import "RCTBridge.h"
#import "RCTEventDispatcher.h"
#import <Hype/Hype.h>

@interface HypeMesh () <HYPStateObserver, HYPNetworkObserver, HYPMessageObserver>
@end

NSMutableDictionary *activeInstances;
NSData *instanceName;

@implementation HypeMesh
+ (void) initialize
{
    if (!activeInstances)
       activeInstances = [[NSMutableDictionary alloc]init];
        
    if (!instanceName)
       instanceName = [[NSData alloc]init];
}

 
@synthesize bridge = _bridge;

RCT_EXPORT_MODULE();


RCT_EXPORT_METHOD(requestHypeToStart) {
  [self requestHypeToStarts];
}

RCT_EXPORT_METHOD(requestHypeToStop) {
  [self requestHypeToStops];
}

RCT_EXPORT_METHOD(setInstanceName: (NSString *)text) {
    NSLog(@"setting custom instance name %@", text);
    NSData* data = [text dataUsingEncoding:NSUTF8StringEncoding];
  instanceName = data;
  NSLog(@"instance name is now %@", instanceName);
}

RCT_EXPORT_METHOD(sendMessage: (NSString *)text instance:(NSString *)instance) {
    [self sendMess:text instance:instance];
}

RCT_EXPORT_METHOD(instanceId:(RCTResponseSenderBlock)callback) {
    callback(@[[NSNull null], [self getInstanceId]]);
}

-(NSString*)getInstanceId
{
    HYP * myInstance = [HYP instance];
    NSString *myId = myInstance.domesticInstance.stringIdentifier;
    return myId;
}

- (void)requestHypeToStarts
{
    // Adding itself as an Hype state observer makes sure that the application gets
    // notifications for lifecycle events being triggered by the Hype framework. These
    // events include starting and stopping, as well as some error handling.
    [[HYP instance] addStateObserver:self];

    // Network observer notifications include other devices entering and leaving the
    // network. When a device is found all observers get a -hype:didFindInstance:
    // notification, and when they leave -hype:didLoseInstance:error: is triggered instead.
    [[HYP instance] addNetworkObserver:self];

    // Message notifications indicate when messages are sent (not available yet) or fail
    // to be sent. Notice that a message being sent does not imply that it has been
    // delivered, only that it has left the device. If considering mesh networking,
    // in which devices will be forwarding content for each other, a message being
    // means that its contents have been flushed out of the output stream, but not
    // that they have reached their destination. This, in turn, is what acknowledgements
    // are used for, but those have not yet available.
    [[HYP instance] addMessageObserver:self];

    // Requesting Hype to start is equivalent to requesting the device to publish
    // itself on the network and start browsing for other devices in proximity. If
    // everything goes well, the -hypeDidStart: delegate method gets called, indicating
    // that the device is actively participating on the network. The 00000000 realm is
    // reserved for test apps, so it's not recommended that apps are shipped with it.
    // For generating a realm go to https://hypelabs.io, login, access the dashboard
    // under the Apps section and click "Create New App". The resulting app should
    // display a realm number. Copy and paste that here.
    [[HYP instance] startWithOptions:@{
                                    HYPOptionRealmKey:@"00000000"
                                   }
                                ];
}

- (void)requestHypeToStops
{
    NSLog(@"trying to stop hype");
    [[HYP instance] stop];
}

- (void)hypeDidStart:(HYP *)hype
{
    // At this point, the device is actively participating on the network. Other devices
    // (instances) can be found at any time and the domestic (this) device can be found
    // by others. When that happens, the two devices should be ready to communicate.
    NSLog(@"Hype started!");
}

- (void)hypeDidStop:(HYP *)hype
              error:(NSError *)error
{
    // The framework has stopped working for some reason. If it was asked to do so (by
    // calling -stop) the error parameter is nil. If, on the other hand, it was forced
    // by some external means, the error parameter indicates the cause. Common causes
    // include the user turning the Bluetooth and/or Wi-Fi adapters off. When the later
    // happens, you shouldn't attempt to start the Hype services again. Instead, the
    // framework triggers a -hypeDidBecomeReady: delegate method if recovery from the
    // failure becomes possible.
    NSLog(@"Hype stoped [%@]", [error localizedDescription]);
}

- (void)hypeDidFailStarting:(HYP *)hype
                      error:(NSError *)error
{
    // Hype couldn't start its services. Usually this means that all adapters (Wi-Fi
    // and Bluetooth) are not on, and as such the device is incapable of participating
    // on the network. The error parameter indicates the cause for the failure. Attempting
    // to restart the services is futile at this point. Instead, the implementation should
    // wait for the framework to trigger a -hypeDidBecomeReady: notification, indicating
    // that recovery is possible, and start the services then.
    NSLog(@"Hype failed starting [%@]", error.localizedDescription);
}

- (void)hypeDidBecomeReady:(HYP *)hype
{
    // This Hype delegate event indicates that the framework believes that it's capable
    // of recovering from a previous start failure. This event is only triggered once.
    // It's not guaranteed that starting the services will result in success, but it's
    // known to be highly likely. If the services are not needed at this point it's
    // possible to delay the execution for later, but it's not guaranteed that the
    // recovery conditions will still hold by then.
    // [self requestHypeToStart];
}

- (void)hype:(HYP *)hype didFindInstance:(HYPInstance *)instance
{
    // Hype instances that are participating on the network are identified by a full
    // UUID, composed by the vendor's realm followed by a unique identifier generated
    // for each instance.

    NSLog(@"Found instance: %@", instance.stringIdentifier);
    [activeInstances setObject:instance  forKey:instance.stringIdentifier];
    [self sendEventWithName:@"didFindInstance"
                                                   body:@{@"data": instance.stringIdentifier}];
    
    // Instances should be strongly kept by some data structure. Their identifiers
    // are useful for keeping track of which instances are ready to communicate.
    // [self.stores setObject:[Store storeWithInstsance:instance]
                    // forKey:instance.stringIdentifier];
    
    // Reloading the table reflects the change
    // [self.tableView reloadData];
}

- (void)hype:(HYP *)hype didLoseInstance:(HYPInstance *)instance
       error:(NSError *)error
{
    // An instance being lost means that communicating with it is no longer possible.
    // This usually happens by the link being broken. This can happen if the connection
    // times out or the device goes out of range. Another possibility is the user turning
    // the adapters off, in which case not only are all instances lost but the framework
    // also stops with an error.
    NSLog(@"Lost instance: %@ [%@]", instance.stringIdentifier, error.localizedDescription);
    if ([activeInstances objectForKey:instance.stringIdentifier]) {
        [activeInstances removeObjectForKey:instance.stringIdentifier];
    } else {
        NSLog(@"No object set for key");
    }
    
    [self sendEventWithName:@"didLoseInstance"
                                                   body:@{@"data": instance.stringIdentifier}];
    
    // Cleaning up is always a good idea. It's not possible to communicate with instances
    // that were previously lost.
    // [self.stores removeObjectForKey:instance.stringIdentifier];
    
    // Reloading the table reflects the change
    // [self.tableView reloadData];
}

- (void)sendMess:(NSString *)text instance:(NSString *)instance
{
    NSLog(@"sending mess");
    if ([activeInstances objectForKey:instance]) {
        NSLog(@"There's an object set for key @\"b\"!");
    } else {
        NSLog(@"No object set for key @\"b\"");
    }
      // When sending content there must be some sort of protocol that both parties
    // understand. In this case, we simply send the text encoded in UTF8. The data
    // must be decoded when received, using the same encoding.
    NSLog(@"Sending: %@ to %@", text, instance);
    NSData * data = [text dataUsingEncoding:NSUTF8StringEncoding];
    HYPMessage * message = [[HYP instance] sendData:data
                                         toInstance:activeInstances[instance]];

}

- (void)hype:(HYP *)hype didReceiveMessage:(HYPMessage *)message fromInstance:(HYPInstance *)instance
{
    NSLog(@"Got a message from: %@", instance.stringIdentifier);
    
    NSString * text = [[NSString alloc] initWithData:message.data
                                            encoding:NSUTF8StringEncoding];
    
    // Store * store = [self.stores objectForKey:instance.stringIdentifier];
    
    // Storing the message triggers a reload update in the chat view controller
    // [store addMessage:message];

      [self sendEventWithName:@"MessageRecieved"
                                                   body:@{@"data": text,
                                                   @"from": instance.stringIdentifier
                                               }];
    
    
}

- (void)hype:(HYP *)hype didFailSending:(HYPMessage *)message toInstance:(HYPInstance *)instance
       error:(NSError *)error
{
    // Sending messages can fail for a lot of reasons, such as the adapters
    // (Bluetooth and Wi-Fi) being turned off by the user while the process
    // of sending the data is still ongoing. The error parameter describes
    // the cause for the failure.
    NSLog(@"Failed to send message: %lu [%@]", (unsigned long)message.identifier, error.localizedDescription);
}

@end
