//
//  ImageViewController.swift
//  ImageViewer
//
//  Created by Kristian Angyal on 01/08/2016.
//  Copyright © 2016 MailOnline. All rights reserved.
//

import UIKit
import AVFoundation

extension VideoView: ItemView {}

class VideoViewController: ItemBaseController<VideoView> {

    fileprivate let swipeToDismissFadeOutAccelerationFactor: CGFloat = 6

    let fetchURL: FetchURLBlock
    var videoURL: URL?
    var player: AVPlayer?
    unowned let scrubber: VideoScrubber

    let fullHDScreenSizeLandscape = CGSize(width: 1920, height: 1080)
    let fullHDScreenSizePortrait = CGSize(width: 1080, height: 1920)
    let embeddedPlayButton = UIButton.circlePlayButton(70)
    
    private var autoPlayStarted: Bool = false
    private var autoPlayEnabled: Bool = false
    
    private var isObservePlayer: Bool = false

    init(index: Int, itemCount: Int, fetchImageBlock: @escaping FetchImageBlock, videoURL: @escaping FetchURLBlock, scrubber: VideoScrubber, configuration: GalleryConfiguration, isInitialController: Bool = false) {

        self.fetchURL = videoURL
        self.scrubber = scrubber
        
        ///Only those options relevant to the paging VideoViewController are explicitly handled here, the rest is handled by ItemViewControllers
        for item in configuration {
            
            switch item {
                
            case .videoAutoPlay(let enabled):
                autoPlayEnabled = enabled
                
            default: break
            }
        }

        super.init(index: index, itemCount: itemCount, fetchImageBlock: fetchImageBlock, configuration: configuration, isInitialController: isInitialController)
        
        self.fetchURL { [weak self] url in
            //TODO: Display video unavailable video=)
            guard let url = url else { return }
            self?.videoURL = url
            self?.player = AVPlayer(url: url)
            
            guard let welf = self else { return }
            welf.player?.addObserver(welf, forKeyPath: "status", options: NSKeyValueObservingOptions.new, context: nil)
            welf.player?.addObserver(welf, forKeyPath: "rate", options: NSKeyValueObservingOptions.new, context: nil)
            welf.isObservePlayer = true
            welf.scrubber.player = welf.player
            
            if welf.itemView.player == nil {
                welf.itemView.player = welf.player
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if isInitialController == true { embeddedPlayButton.alpha = 0 }

        embeddedPlayButton.autoresizingMask = [.flexibleTopMargin, .flexibleLeftMargin, .flexibleBottomMargin, .flexibleRightMargin]
        self.view.addSubview(embeddedPlayButton)
        embeddedPlayButton.center = self.view.boundsCenter

        embeddedPlayButton.addTarget(self, action: #selector(playVideoEmbedButtonTapped), for: .touchUpInside)

        self.itemView.player = player
        self.itemView.contentMode = .scaleAspectFill
        self.scrubber.sendButton.addTarget(self, action: #selector(sendVideo(sender:)), for: .touchUpInside)
        self.scrubber.onDidChangePlaybackState = { [weak self] _ in
            self?.updateEmbeddedPlayButtonVisibility()
        }
    }

    override func viewWillAppear(_ animated: Bool) {

        UIApplication.shared.beginReceivingRemoteControlEvents()

        super.viewWillAppear(animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(self)

        UIApplication.shared.endReceivingRemoteControlEvents()

        super.viewWillDisappear(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        performAutoPlay()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        self.player?.pause()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let isLandscape = itemView.bounds.width >= itemView.bounds.height
        itemView.bounds.size = aspectFitSize(forContentOfSize: isLandscape ? fullHDScreenSizeLandscape : fullHDScreenSizePortrait, inBounds: self.scrollView.bounds.size)
        itemView.center = scrollView.boundsCenter
    }
    
    override func scrollViewDidSingleTap() {
       switchPlayblackState()
    }
    
    private func switchPlayblackState() {
        
        switch scrubber.playbackState {
        case .paused: scrubber.play()
        case .finished: scrubber.replay()
        case .playing: scrubber.pause()
        }
    }
    
    private func updateEmbeddedPlayButtonVisibility() {
        embeddedPlayButton.alpha = scrubber.playbackState == .playing ? 0.0 : 1.0
    }
    
    @objc func playVideoEmbedButtonTapped() {
        switchPlayblackState()
    }
    
    @objc func sendVideo(sender: UIButton) {
        delegate?.itemControllerDidSendTap(self)
    }

    override func closeDecorationViews(_ duration: TimeInterval) {

        UIView.animate(withDuration: duration, animations: { [weak self] in

            self?.embeddedPlayButton.alpha = 0
            self?.itemView.previewImageView.alpha = 1
        })
    }

    override func presentItem(alongsideAnimation: () -> Void, completion: @escaping () -> Void) {

        let circleButtonAnimation = {

            UIView.animate(withDuration: 0.15, animations: { [weak self] in
                self?.embeddedPlayButton.alpha = 1
            })
        }

        super.presentItem(alongsideAnimation: alongsideAnimation) {

            circleButtonAnimation()
            completion()
        }
    }

    override func displacementTargetSize(forSize size: CGSize) -> CGSize {

        let isLandscape = itemView.bounds.width >= itemView.bounds.height
        return aspectFitSize(forContentOfSize: isLandscape ? fullHDScreenSizeLandscape : fullHDScreenSizePortrait, inBounds: rotationAdjustedBounds().size)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {

        if keyPath == "rate" || keyPath == "status" {

            fadeOutEmbeddedPlayButton()
        }

        else if keyPath == "contentOffset" {

            handleSwipeToDismissTransition()
        }

        super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
    }

    func handleSwipeToDismissTransition() {

        guard let _ = swipingToDismiss else { return }

        embeddedPlayButton.center.y = view.center.y - scrollView.contentOffset.y
    }

    func fadeOutEmbeddedPlayButton() {

        if player?.isPlaying() == true && embeddedPlayButton.alpha != 0  {

            UIView.animate(withDuration: 0.3, animations: { [weak self] in

                self?.embeddedPlayButton.alpha = 0
            })
        }
    }

    override func remoteControlReceived(with event: UIEvent?) {

        if let event = event {

            if event.type == .remoteControl {

                switch event.subtype {

                case .remoteControlTogglePlayPause:

                    if self.player?.isPlaying() == true  {

                        self.player?.pause()
                    }
                    else {

                        self.player?.play()
                    }

                case .remoteControlPause:

                    self.player?.pause()

                case .remoteControlPlay:

                    self.player?.play()

                case .remoteControlPreviousTrack:

                    self.player?.pause()
                    self.player?.seek(to: CMTime(value: 0, timescale: 1))
                    self.player?.play()

                default:

                    break
                }
            }
        }
    }
    
    private func performAutoPlay() {
        guard autoPlayEnabled else { return }
        guard autoPlayStarted == false else { return }
        
        autoPlayStarted = true
        embeddedPlayButton.isHidden = true
        scrubber.play()
    }
}
