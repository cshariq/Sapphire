////
////  IMessageService.h
////  Sapphire
////
////  Created by Shariq Charolia on 2025-09-18.
////
//
//
//#import <Foundation/Foundation.h>
//
//// Define a block (closure) to pass events back to Swift
//typedef void (^MessageHandler)(NSDictionary * _Nonnull messageData);
//typedef void (^CallHandler)(NSDictionary * _Nonnull callData);
//
//// Make the class visible to Swift
//NS_ASSUME_NONNULL_BEGIN
//
//@interface IMessageService : NSObject
//
//@property (nonatomic, copy) MessageHandler onMessageReceived;
//@property (nonatomic, copy) CallHandler onCallStatusChanged;
//
//+ (instancetype)sharedInstance;
//
//- (void)sendMessage:(NSString *)messageText toChat:(NSString *)chatGuid;
//- (void)sendReaction:(NSString *)reaction toMessage:(NSString *)messageGuid inChat:(NSString *)chatGuid atPartIndex:(NSInteger)partIndex;
//- (void)answerCall:(NSString *)callUUID;
//- (void)hangupCall:(NSString *)callUUID;
//
//@end
//
//NS_ASSUME_NONNULL_END
