// Makes the website's people as Memoji stickers: trimmed, transparent PNGs rendered with macOS's
// private AvatarKit framework. Each person is described in memoji-people.json (hair, skin, facial
// hair, glasses, headwear, earrings, pose); anything left out stays at the neutral Memoji's
// default. Everyone wears AirPods.
//
//   clang -fobjc-arc -framework Foundation -framework AppKit tools/memoji.m -o /tmp/memoji
//   /tmp/memoji tools/memoji-people.json /tmp/memoji-out
//
// Then shrink them into docs/people/ with `sips -Z 192`. Names of presets and colors: run
// `/tmp/memoji --list <category>`. AvatarKit is private, so this can break with any macOS
// update (it works on macOS 27).
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <dlfcn.h>
#import <objc/message.h>

// AvatarKit's preset categories.
enum { Head = 0, Hair = 1, FacialHair = 2, Headwear = 4, Eyewear = 5, Eyebrows = 8, Age = 12,
       Highlights = 15, EarpieceLeft = 25, EarpieceRight = 26, EarringLeft = 30, EarringRight = 31 };

static NSArray *Presets(long category) {
  return ((id(*)(id,SEL,long))objc_msgSend)(NSClassFromString(@"AVTPreset"), @selector(availablePresetsForCategory:), category);
}
static NSArray *Colors(long category) {
  return ((id(*)(id,SEL,long))objc_msgSend)(NSClassFromString(@"AVTPreset"), @selector(colorPresetsForCategory:), category);
}

static void SetPreset(id memoji, long category, NSString *identifier) {
  if (!identifier) return;
  id preset = ((id(*)(id,SEL,long,id))objc_msgSend)(NSClassFromString(@"AVTPreset"), @selector(presetWithCategory:identifier:), category, identifier);
  if (!preset) { fprintf(stderr, "  no preset %s in category %ld\n", identifier.UTF8String, category); return; }
  ((void(*)(id,SEL,id,long))objc_msgSend)(memoji, @selector(setPreset:forCategory:), preset, category);
}

static void SetColor(id memoji, long category, NSString *name) {
  if (!name) return;
  for (id color in Colors(category)) {
    if ([[color valueForKey:@"name"] isEqual:name]) {
      ((void(*)(id,SEL,id,long))objc_msgSend)(memoji, @selector(setColorPreset:forCategory:), color, category);
      return;
    }
  }
  fprintf(stderr, "  no color %s in category %ld\n", name.UTF8String, category);
}

// Crops to the sticker's visible pixels, centered in a square with a little room.
static CGImageRef Trim(CGImageRef image) {
  size_t w = CGImageGetWidth(image), h = CGImageGetHeight(image);
  CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  uint8_t *px = calloc(w * h, 4);
  CGContextRef ctx = CGBitmapContextCreate(px, w, h, 8, w * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
  CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), image);
  long minX = w, minY = h, maxX = -1, maxY = -1;
  for (size_t y = 0; y < h; y++) for (size_t x = 0; x < w; x++)
    if (px[(y * w + x) * 4 + 3] > 8) { minX = MIN(minX, (long)x); maxX = MAX(maxX, (long)x); minY = MIN(minY, (long)y); maxY = MAX(maxY, (long)y); }
  free(px);
  CGContextRelease(ctx);
  if (maxX < 0) { CGColorSpaceRelease(space); return CGImageRetain(image); }
  long side = MAX(maxX - minX, maxY - minY) + 8;
  long cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
  CGContextRef out = CGBitmapContextCreate(NULL, side, side, 8, 0, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
  // Rows were scanned top down; CoreGraphics draws bottom up.
  CGContextDrawImage(out, CGRectMake(side / 2 - cx, side / 2 - ((long)h - 1 - cy), w, h), image);
  CGImageRef result = CGBitmapContextCreateImage(out);
  CGContextRelease(out);
  CGColorSpaceRelease(space);
  return result;
}

static void Render(id memoji, NSString *pose, NSString *path) {
  id config = ((id(*)(id,SEL,id,id))objc_msgSend)(NSClassFromString(@"AVTStickerConfiguration"),
    @selector(stickerConfigurationForMemojiInStickerPack:stickerName:), @"posesPack", pose);
  if (!config) { fprintf(stderr, "  no pose %s\n", pose.UTF8String); return; }
  id generator = ((id(*)(id,SEL,id))objc_msgSend)([NSClassFromString(@"AVTStickerGenerator") alloc], @selector(initWithAvatar:), memoji);
  __block BOOL done = NO;
  ((void(*)(id,SEL,id,void(^)(NSImage *)))objc_msgSend)(generator, @selector(stickerImageWithConfiguration:completionHandler:), config, ^(NSImage *image) {
    CGImageRef cg = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (cg) {
      CGImageRef trimmed = Trim(cg);
      NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:trimmed];
      [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
      CGImageRelease(trimmed);
    }
    done = YES;
  });
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:30];
  while (!done && limit.timeIntervalSinceNow > 0)
    [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
  fprintf(stderr, "%s %s\n", done ? "wrote" : "timed out", path.UTF8String);
}

int main(int argc, char **argv) { @autoreleasepool {
  [NSApplication sharedApplication];
  dlopen("/System/Library/PrivateFrameworks/AvatarKit.framework/AvatarKit", RTLD_NOW);

  if (argc == 3 && strcmp(argv[1], "--list") == 0) {
    long category = atol(argv[2]);
    NSMutableArray *presets = [NSMutableArray array], *colors = [NSMutableArray array];
    for (id p in Presets(category)) [presets addObject:[p valueForKey:@"identifier"]];
    for (id c in Colors(category)) [colors addObject:[c valueForKey:@"name"]];
    printf("presets: %s\ncolors: %s\n", [presets componentsJoinedByString:@", "].UTF8String, [colors componentsJoinedByString:@", "].UTF8String);
    return 0;
  }
  if (argc < 3) { fprintf(stderr, "usage: memoji <people.json> <outdir> | memoji --list <category>\n"); return 1; }

  NSArray *people = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:nil];
  NSString *dir = @(argv[2]);
  [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

  [people enumerateObjectsUsingBlock:^(NSDictionary *person, NSUInteger i, BOOL *stop) {
    id memoji = [[NSClassFromString(@"AVTMemoji") alloc] init];
    SetPreset(memoji, Age, @"adult");
    SetColor(memoji, Head, person[@"skin"]);
    SetPreset(memoji, Hair, person[@"hair"]);
    for (NSNumber *category in @[@(Hair), @(Eyebrows), @(FacialHair)]) SetColor(memoji, category.longValue, person[@"hairColor"]);
    SetPreset(memoji, Highlights, person[@"highlights"]);
    SetColor(memoji, Highlights, person[@"highlightsColor"]);
    SetPreset(memoji, Eyebrows, person[@"eyebrows"]);
    SetPreset(memoji, FacialHair, person[@"facialHair"]);
    SetPreset(memoji, Eyewear, person[@"eyewear"]);
    SetColor(memoji, Eyewear, person[@"eyewearColor"]);
    SetPreset(memoji, Headwear, person[@"headwear"]);
    SetColor(memoji, Headwear, person[@"headwearColor"]);
    for (NSNumber *category in @[@(EarringLeft), @(EarringRight)]) {
      SetPreset(memoji, category.longValue, person[@"earrings"]);
      SetColor(memoji, category.longValue, person[@"earringsColor"]);
    }
    SetPreset(memoji, EarpieceLeft, @"airPods");
    SetPreset(memoji, EarpieceRight, @"airPods");

    NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"memoji-%02lu.png", (unsigned long)i + 1]];
    Render(memoji, person[@"pose"] ?: @"happy", path);
  }];
}}
