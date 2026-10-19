#include <time.h>
#include <sys/resource.h>
#include "Diagnostics.h"
#import <Foundation/Foundation.h>
#import "TrackJournal.h"
#import "NativeErrorLog.h"
#import "WireProto.h"
#include <assert.h>

// Построение настоящих байтов сервиса Offline (номера полей — из дескриптора,
// analysis/offline-esperanto-service.md), чтобы журнал разбирал ровно тот формат,
// который приходит с устройства.
static NSData *join(NSArray<NSData *> *parts) {
    NSMutableData *data = [NSMutableData data];
    for (NSData *part in parts) [data appendData:part];
    return data;
}
static NSData *text(NSString *value) { return [value dataUsingEncoding:NSUTF8StringEncoding]; }
static NSData *floatField(unsigned number, float value) {
    uint32_t bits = 0; memcpy(&bits, &value, 4);
    NSMutableData *data = [NSMutableData data];
    uint8_t tag = (uint8_t)((number << 3) | 5);
    [data appendBytes:&tag length:1];
    for (unsigned i = 0; i < 4; i++) { uint8_t byte = (bits >> (i * 8)) & 0xff; [data appendBytes:&byte length:1]; }
    return data;
}
static NSData *item(NSString *uri, NSUInteger state, NSUInteger progress) {
    return SAPProtoBytes(1, join(@[SAPProtoBytes(1, text(uri)), SAPProtoInteger(2, state), SAPProtoInteger(4, progress)]));
}
static NSData *itemsResponse(NSArray<NSData *> *items) { return join(items); }
static NSData *contextResponse(NSString *entity, NSUInteger state, float percent, NSArray<NSData *> *items) {
    NSData *context = SAPProtoBytes(1, join(@[SAPProtoBytes(1, text(entity)), SAPProtoInteger(2, state), floatField(3, percent)]));
    NSMutableData *info = [context mutableCopy];
    for (NSData *value in items) [info appendData:SAPProtoBytes(2, [value subdataWithRange:NSMakeRange(2, value.length - 2)])];
    return SAPProtoBytes(1, info);
}
static NSData *progressResponse(uint64_t queued, uint64_t downloaded, uint64_t total, uint64_t speed, float percent) {
    return SAPProtoBytes(1, join(@[SAPProtoInteger(1, queued), SAPProtoInteger(3, downloaded), SAPProtoInteger(5, total),
        SAPProtoInteger(8, speed), floatField(9, percent), SAPProtoInteger(10, 120), SAPProtoInteger(7, 1)]));
}

int main(void){@autoreleasepool {
 SAPDiagnosticsSetEnabled(true);SAPJournalReset();SAPJournalDrainForTesting();
 NSMutableArray *items=[NSMutableArray array];
 for(unsigned i=0;i<3000;i++)[items addObject:item([NSString stringWithFormat:@"spotify:track:%022u",i],3,100)];
 SAPJournalObserveCall(@"GetItems",nil,join(items),@"benchmark");SAPJournalDrainForTesting();
 assert([SAPJournalReport()[@"tracked_tracks"] unsignedIntegerValue]==3000);
 struct timespec cpu0,cpu1,wall0,wall1;clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&cpu0);clock_gettime(CLOCK_MONOTONIC,&wall0);
 const unsigned count=8;NSURL *lastText,*lastJSON;
 for(unsigned i=0;i<count;i++){@autoreleasepool {
#if BENCH_V4
 NSDictionary *report=SAPJournalReport();NSURL *txt=SAPJournalWriteTableSnapshot(report),*json=SAPJournalWriteReportSnapshot(report);
#else
 NSURL *txt=SAPJournalWriteTable(),*json=SAPJournalWriteReport();NSDictionary *report=SAPJournalReport();
#endif
 assert(txt&&json&&report[@"log_file"]);lastText=txt;lastJSON=json;
 }}
 clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&cpu1);clock_gettime(CLOCK_MONOTONIC,&wall1);
 struct rusage usage;getrusage(RUSAGE_SELF,&usage);
 NSUInteger bytes=[NSData dataWithContentsOfURL:lastJSON].length+[NSData dataWithContentsOfURL:lastText].length;
 printf("{\"cpu_ms_per_export\":%.3f,\"wall_ms_per_export\":%.3f,\"max_rss_bytes\":%ld,\"fs_output_blocks\":%ld,\"bytes_per_export\":%lu,\"exports\":%u,\"tracks\":3000}\n",((cpu1.tv_sec-cpu0.tv_sec)*1e3+(cpu1.tv_nsec-cpu0.tv_nsec)/1e6)/count,((wall1.tv_sec-wall0.tv_sec)*1e3+(wall1.tv_nsec-wall0.tv_nsec)/1e6)/count,usage.ru_maxrss,usage.ru_oublock,bytes,count);
 return 0;
}}
