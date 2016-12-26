//
//  APPLView.m
//  MetalVertex
//
//  Created by cfq on 2016/10/24.
//  Copyright © 2016年 Dlodlo. All rights reserved.
//

#import "APPLView.h"

@implementation APPLView

{
    @private
    __weak CAMetalLayer *_metalLayer;
    BOOL _layerSizeDidUpdate;
    
    id <MTLTexture> _depthTex;
    id <MTLTexture> _stencilTex;
    id <MTLTexture> _mssaTex;
}

@synthesize currentDrawable      = _currentDrawable;
@synthesize renderPassDescriptor = _renderPassDescriptor;

+ (Class)layerClass
{
    return [CAMetalLayer class];
}

- (void)initCommon
{
    self.opaque          = YES;
    self.backgroundColor = nil;
    
    _metalLayer = (CAMetalLayer *)self.layer;
    
    _device = MTLCreateSystemDefaultDevice();
    
    _metalLayer.device          = _device;
    _metalLayer.pixelFormat     = MTLPixelFormatBGRA8Unorm;
    _metalLayer.frame = self.frame;
    // this is the default but if we wanted to perform compute on the final rendering layer we could set this to no
    _metalLayer.framebufferOnly = YES;

}

- (void)didMoveToWindow
{
    self.contentScaleFactor = self.window.screen.nativeScale;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    
    if(self)
    {
        [self initCommon];
    }
    
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    
    if(self)
    {
        [self initCommon];
    }
    return self;
}

- (void)releaseTextures
{
    _depthTex   = nil;
    _stencilTex = nil;
    _mssaTex    = nil;
}

- (void)setupRenderPassDescriptorForTexture:(id <MTLTexture>) texture
{
    // create lazily
    if (_renderPassDescriptor == nil)
        _renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    
    // create a color attachment every frame since we have to recreate the texture every frame
    MTLRenderPassColorAttachmentDescriptor *colorAttachment = _renderPassDescriptor.colorAttachments[0];
    colorAttachment.texture = texture;
    
    // make sure to clear every frame for best performance
    colorAttachment.loadAction = MTLLoadActionClear;
    colorAttachment.clearColor = MTLClearColorMake(0.65f, 0.65f, 0.65f, 1.0f);
    
    // if sample count is greater than 1, render into using MSAA, then resolve into our color texture
    if(_sampleCount > 1)
    {
        BOOL doUpdate =     ( _mssaTex.width       != texture.width  )
        ||  ( _mssaTex.height      != texture.height )
        ||  ( _mssaTex.sampleCount != _sampleCount   );
        
        if(!_mssaTex || (_mssaTex && doUpdate))
        {
            MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: MTLPixelFormatBGRA8Unorm
                                                                                            width: texture.width
                                                                                           height: texture.height
                                                                                        mipmapped: NO];
            desc.textureType = MTLTextureType2DMultisample;
            
            // sample count was specified to the view by the renderer.
            // this must match the sample count given to any pipeline state using this render pass descriptor
            desc.sampleCount = _sampleCount;
            
            _mssaTex = [_device newTextureWithDescriptor: desc];
        }
        
        // When multisampling, perform rendering to _msaaTex, then resolve
        // to 'texture' at the end of the scene
        colorAttachment.texture = _mssaTex;
        colorAttachment.resolveTexture = texture;
        
        // set store action to resolve in this case
        colorAttachment.storeAction = MTLStoreActionMultisampleResolve;
    }
    else
    {
        // store only attachments that will be presented to the screen, as in this case
        colorAttachment.storeAction = MTLStoreActionStore;
    } // color0
    
    // Now create the depth and stencil attachments
    
    if(_depthPixelFormat != MTLPixelFormatInvalid)
    {
        BOOL doUpdate =     ( _depthTex.width       != texture.width  )
        ||  ( _depthTex.height      != texture.height )
        ||  ( _depthTex.sampleCount != _sampleCount   );
        
        if(!_depthTex || doUpdate)
        {
            //  If we need a depth texture and don't have one, or if the depth texture we have is the wrong size
            //  Then allocate one of the proper size
            MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: _depthPixelFormat
                                                                                            width: texture.width
                                                                                           height: texture.height
                                                                                        mipmapped: NO];
            
            desc.textureType = (_sampleCount > 1) ? MTLTextureType2DMultisample : MTLTextureType2D;
            desc.sampleCount = _sampleCount;
            
            _depthTex = [_device newTextureWithDescriptor: desc];
            
            MTLRenderPassDepthAttachmentDescriptor *depthAttachment = _renderPassDescriptor.depthAttachment;
            depthAttachment.texture = _depthTex;
            depthAttachment.loadAction = MTLLoadActionClear;
            depthAttachment.storeAction = MTLStoreActionDontCare;
            depthAttachment.clearDepth = 1.0;
        }
    } // depth
    
    if(_stencilPixelFormat != MTLPixelFormatInvalid)
    {
        BOOL doUpdate  =    ( _stencilTex.width       != texture.width  )
        ||  ( _stencilTex.height      != texture.height )
        ||  ( _stencilTex.sampleCount != _sampleCount   );
        
        if(!_stencilTex || doUpdate)
        {
            //  If we need a stencil texture and don't have one, or if the depth texture we have is the wrong size
            //  Then allocate one of the proper size
            MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: _stencilPixelFormat
                                                                                            width: texture.width
                                                                                           height: texture.height
                                                                                        mipmapped: NO];
            
            desc.textureType = (_sampleCount > 1) ? MTLTextureType2DMultisample : MTLTextureType2D;
            desc.sampleCount = _sampleCount;
            
            _stencilTex = [_device newTextureWithDescriptor: desc];
            
            MTLRenderPassStencilAttachmentDescriptor* stencilAttachment = _renderPassDescriptor.stencilAttachment;
            stencilAttachment.texture = _stencilTex;
            stencilAttachment.loadAction = MTLLoadActionClear;
            stencilAttachment.storeAction = MTLStoreActionDontCare;
            stencilAttachment.clearStencil = 0;
        }
    } //stencil
}

- (MTLRenderPassDescriptor *)renderPassDescriptor
{
    id <CAMetalDrawable> drawable = self.currentDrawable;
    if(!drawable)
    {
        NSLog(@">> ERROR: Failed to get a drawable!");
        _renderPassDescriptor = nil;
    }
    else
    {
        [self setupRenderPassDescriptorForTexture: drawable.texture];
    }
    
    return _renderPassDescriptor;
}


- (id <CAMetalDrawable>)currentDrawable
{
    if (_currentDrawable == nil)
        _currentDrawable = [_metalLayer nextDrawable];
    
    return _currentDrawable;
}

- (void)display
{
    // Create autorelease pool per frame to avoid possible deadlock situations
    // because there are 3 CAMetalDrawables sitting in an autorelease pool.
    
    @autoreleasepool
    {
        // handle display changes here
        if(_layerSizeDidUpdate)
        {
            // set the metal layer to the drawable size in case orientation or size changes
            CGSize drawableSize = self.bounds.size;
            drawableSize.width  *= self.contentScaleFactor;
            drawableSize.height *= self.contentScaleFactor;
            
            _metalLayer.drawableSize = drawableSize;
            
            // renderer delegate method so renderer can resize anything if needed
            [_delegate reshape:self];
            
            _layerSizeDidUpdate = NO;
        }
        
        // rendering delegate method to ask renderer to draw this frame's content
        [self.delegate render:self];
        
        // do not retain current drawable beyond the frame.
        // There should be no strong references to this object outside of this view class
        _currentDrawable    = nil;
    }
}

- (void)setContentScaleFactor:(CGFloat)contentScaleFactor
{
    [super setContentScaleFactor:contentScaleFactor];
    
    _layerSizeDidUpdate = YES;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    _layerSizeDidUpdate = YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}


@end