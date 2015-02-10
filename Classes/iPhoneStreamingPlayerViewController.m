//
//  iPhoneStreamingPlayerViewController.m
//  iPhoneStreamingPlayer
//
//  Created by Matt Gallagher on 28/10/08.
//  Copyright Matt Gallagher 2008. All rights reserved.
//
//  This software is provided 'as-is', without any express or implied
//  warranty. In no event will the authors be held liable for any damages
//  arising from the use of this software. Permission is granted to anyone to
//  use this software for any purpose, including commercial applications, and to
//  alter it and redistribute it freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//     claim that you wrote the original software. If you use this software
//     in a product, an acknowledgment in the product documentation would be
//     appreciated but is not required.
//  2. Altered source versions must be plainly marked as such, and must not be
//     misrepresented as being the original software.
//  3. This notice may not be removed or altered from any source
//     distribution.
//

#import "iPhoneStreamingPlayerViewController.h"
#import <QuartzCore/CoreAnimation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <CFNetwork/CFNetwork.h>

@implementation iPhoneStreamingPlayerViewController

//
// setButtonImage:
//
// Used to change the image on the playbutton. This method exists for
// the purpose of inter-thread invocation because
// the observeValueForKeyPath:ofObject:change:context: method is invoked
// from secondary threads and UI updates are only permitted on the main thread.
//
// Parameters:
//    image - the image to set on the play button.
//
- (void)setButtonImage:(UIImage *)image
{
	[button.layer removeAllAnimations];
	if (!image)
	{
		[button setImage:[UIImage imageNamed:@"playbutton.png"] forState:0];
	}
	else
	{
		[button setImage:image forState:0];

		if ([button.currentImage isEqual:[UIImage imageNamed:@"loadingbutton.png"]])
		{
			[self spinButton];
		}
	}
}

//
// destroyStreamer
//
// Removes the streamer and the UI update timer
//
- (void)destroyStreamer
{
	if (streamer)
	{
		[progressUpdateTimer invalidate];
		progressUpdateTimer = nil;

		[streamer stop];
		streamer = nil;
	}
}

//
// createStreamer
//
// Creates or recreates the AudioStreamer object.
//
- (void)createStreamer
{
	if (streamer)
	{
		return;
	}

	[self destroyStreamer];

	NSString *escapedValue =
		(__bridge_transfer NSString *)CFURLCreateStringByAddingPercentEscapes(
			nil,
			(__bridge CFStringRef)downloadSourceField.text,
			NULL,
			NULL,
			kCFStringEncodingUTF8);

	NSURL *url = [NSURL URLWithString:escapedValue];
	streamer = [iPhoneStreamer streamWithURL:url];
	[streamer setDelegate:self];

	progressUpdateTimer =
		[NSTimer
			scheduledTimerWithTimeInterval:0.1
			target:self
			selector:@selector(updateProgress:)
			userInfo:nil
			repeats:YES];
}

//
// viewDidLoad
//
// Creates the volume slider, sets the default path for the local file and
// creates the streamer immediately if we already have a file at the local
// location.
//
- (void)viewDidLoad
{
	[super viewDidLoad];

	MPVolumeView *volumeView = [[MPVolumeView alloc] initWithFrame:volumeSlider.bounds];
	[volumeSlider addSubview:volumeView];
	[volumeView sizeToFit];

	[self setButtonImage:[UIImage imageNamed:@"playbutton.png"]];
}

//
// spinButton
//
// Shows the spin button when the audio is loading. This is largely irrelevant
// now that the audio is loaded from a local file.
//
- (void)spinButton
{
	[CATransaction begin];
	[CATransaction setValue:@YES forKey:kCATransactionDisableActions];
	CGRect frame = [button frame];
	button.layer.anchorPoint = CGPointMake(0.5, 0.5);
	button.layer.position = CGPointMake(frame.origin.x + 0.5f * frame.size.width, frame.origin.y + 0.5f * frame.size.height);
	[CATransaction commit];

	[CATransaction begin];
	[CATransaction setValue:@NO forKey:kCATransactionDisableActions];
	[CATransaction setValue:@2.0 forKey:kCATransactionAnimationDuration];

	CABasicAnimation *animation;
	animation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
	animation.fromValue = @0.0;
	animation.toValue = @(2.0 * M_PI);
	animation.timingFunction = [CAMediaTimingFunction functionWithName: kCAMediaTimingFunctionLinear];
	animation.delegate = self;
	[button.layer addAnimation:animation forKey:@"rotationAnimation"];

	[CATransaction commit];
}

//
// animationDidStop:finished:
//
// Restarts the spin animation on the button when it ends. Again, this is
// largely irrelevant now that the audio is loaded from a local file.
//
// Parameters:
//    theAnimation - the animation that rotated the button.
//    finished - is the animation finised?
//
- (void)animationDidStop:(CAAnimation *)theAnimation finished:(BOOL)finished
{
	if (finished)
	{
		[self spinButton];
	}
}

//
// buttonPressed:
//
// Handles the play/stop button. Creates, observes and starts the
// audio streamer when it is a play button. Stops the audio streamer when
// it isn't.
//
// Parameters:
//    sender - normally, the play/stop button.
//
- (IBAction)buttonPressed:(id)sender
{
	if ([button.currentImage isEqual:[UIImage imageNamed:@"playbutton.png"]])
	{
		[downloadSourceField resignFirstResponder];

		[self createStreamer];
		[self setButtonImage:[UIImage imageNamed:@"loadingbutton.png"]];
		[streamer start];
	}
	else
	{
		[streamer stop];
	}
}

//
// sliderMoved:
//
// Invoked when the user moves the slider
//
// Parameters:
//    aSlider - the slider (assumed to be the progress slider)
//
- (IBAction)sliderMoved:(UISlider *)aSlider
{
	double duration;
	if ([streamer duration:&duration])
	{
		double newSeekTime = (aSlider.value / 100.0) * duration;
		[streamer seekToTime:newSeekTime];
	}
}

//
// streamerStatusDidChange:
//
// Invoked when the AudioStreamer
// reports that its playback status has changed.
//
- (void)streamerStatusDidChange:(AudioStreamer *)sender
{
	if ([sender isWaiting])
	{
		[self setButtonImage:[UIImage imageNamed:@"loadingbutton.png"]];
	}
	else if ([sender isPlaying])
	{
		[self setButtonImage:[UIImage imageNamed:@"stopbutton.png"]];
	}
	else if ([sender isDone])
	{
		[self destroyStreamer];
		[self setButtonImage:[UIImage imageNamed:@"playbutton.png"]];
	}
}

//
// updateProgress:
//
// Invoked when the AudioStreamer
// reports that its playback progress has changed.
//
- (void)updateProgress:(NSTimer *)updatedTimer
{
	double bitRate;
	if ([streamer calculatedBitRate:&bitRate])
	{
		double progress;
		double duration;

		if ([streamer duration:&duration] && [streamer progress:&progress])
		{
			[positionLabel setText:
				[NSString stringWithFormat:@"Time Played: %@/%@",
					[self stringFromSeconds:progress],
					[self stringFromSeconds:duration]]];
			[progressSlider setEnabled:YES];
			[progressSlider setValue:100.f * (float)(progress / duration)];
		}
		else
		{
			if ([streamer isPlaying]) {
				[positionLabel setText:@"Time Played:"];
			}
			[progressSlider setEnabled:NO];
			[progressSlider setValue:0];
		}
	}
	else
	{
		positionLabel.text = @"Time Played:";
	}

	NSString *currentSong = [streamer currentSong];
	if (currentSong && [streamInfoBody text] != currentSong)
	{
		[streamInfoTitle setText:@"Current song:"];
		[streamInfoBody setText:currentSong];
	}
	else if (!currentSong && ![[streamInfoBody text] isEqualToString:@""])
	{
		[streamInfoTitle setText:@""];
		[streamInfoBody setText:@""];
	}
}

//
// stringFromSeconds:
//
// Converts a CGFloat time, in seconds, into NSString in HH:MM:SS.ss format
//
// Parameters:
//    interval - the time, in seconds, to convert
//
// returns the NSString of the converted time
//
- (NSString *)stringFromSeconds:(double)totalSconds
{
	double seconds = fmod(totalSconds, 60);
	int minutes = (int)floor(fmod(totalSconds / 60, 60));
	int hours = (int)floor(fmod(totalSconds / 3600, 60));
	return [NSString stringWithFormat:@"%02d:%02d:%04.1f", hours, minutes, seconds];
}

//
// textFieldShouldReturn:
//
// Dismiss the text field when done is pressed
//
// Parameters:
//    sender - the text field
//
// returns YES
//
- (BOOL)textFieldShouldReturn:(UITextField *)sender
{
	[sender resignFirstResponder];
	[self createStreamer];
	return YES;
}

//
// dealloc
//
// Releases instance memory.
//
- (void)dealloc
{
	[self destroyStreamer];
	if (progressUpdateTimer)
	{
		[progressUpdateTimer invalidate];
		progressUpdateTimer = nil;
	}
}

@end
