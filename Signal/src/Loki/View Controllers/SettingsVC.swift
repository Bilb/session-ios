
final class SettingsVC : BaseVC, AvatarViewHelperDelegate {
    private var profilePictureToBeUploaded: UIImage?
    private var displayNameToBeUploaded: String?
    private var isEditingDisplayName = false { didSet { handleIsEditingDisplayNameChanged() } }
    
    private lazy var userHexEncodedPublicKey: String = {
        if let masterHexEncodedPublicKey = UserDefaults.standard[.masterHexEncodedPublicKey] {
            return masterHexEncodedPublicKey
        } else {
            return getUserHexEncodedPublicKey()
        }
    }()
    
    // MARK: Components
    private lazy var profilePictureView: ProfilePictureView = {
        let result = ProfilePictureView()
        let size = Values.largeProfilePictureSize
        result.size = size
        result.set(.width, to: size)
        result.set(.height, to: size)
        return result
    }()
    
    private lazy var profilePictureUtilities: AvatarViewHelper = {
        let result = AvatarViewHelper()
        result.delegate = self
        return result
    }()
    
    private lazy var displayNameLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        result.lineBreakMode = .byTruncatingTail
        result.textAlignment = .center
        return result
    }()
    
    private lazy var displayNameTextField: TextField = {
        let result = TextField(placeholder: NSLocalizedString("vc_settings_display_name_text_field_hint", comment: ""), usesDefaultHeight: false)
        result.textAlignment = .center
        return result
    }()
    
    private lazy var copyButton: Button = {
        let result = Button(style: .prominentOutline, size: .medium)
        result.setTitle(NSLocalizedString("copy", comment: ""), for: UIControl.State.normal)
        result.addTarget(self, action: #selector(copyPublicKey), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpGradientBackground()
        setUpNavBarStyle()
        setNavBarTitle(NSLocalizedString("vc_settings_title", comment: ""))
        // Set up navigation bar buttons
        let backButton = UIBarButtonItem(title: "Back", style: .plain, target: nil, action: nil)
        backButton.tintColor = Colors.text
        navigationItem.backBarButtonItem = backButton
        updateNavigationBarButtons()
        // Set up profile picture view
        let profilePictureTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(showEditProfilePictureUI))
        profilePictureView.addGestureRecognizer(profilePictureTapGestureRecognizer)
        profilePictureView.hexEncodedPublicKey = userHexEncodedPublicKey
        profilePictureView.update()
        // Set up display name label
        displayNameLabel.text = OWSProfileManager.shared().profileNameForRecipient(withID: userHexEncodedPublicKey)
        // Set up display name container
        let displayNameContainer = UIView()
        displayNameContainer.addSubview(displayNameLabel)
        displayNameLabel.pin(to: displayNameContainer)
        displayNameContainer.addSubview(displayNameTextField)
        displayNameTextField.pin(to: displayNameContainer)
        displayNameContainer.set(.height, to: 40)
        displayNameTextField.alpha = 0
        let displayNameContainerTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(showEditDisplayNameUI))
        displayNameContainer.addGestureRecognizer(displayNameContainerTapGestureRecognizer)
        // Set up header view
        let headerStackView = UIStackView(arrangedSubviews: [ profilePictureView, displayNameContainer ])
        headerStackView.axis = .vertical
        headerStackView.spacing = Values.smallSpacing
        headerStackView.alignment = .center
        // Set up separator
        let separator = Separator(title: NSLocalizedString("your_session_id", comment: ""))
        // Set up public key label
        let publicKeyLabel = UILabel()
        publicKeyLabel.textColor = Colors.text
        publicKeyLabel.font = Fonts.spaceMono(ofSize: isIPhone5OrSmaller ? Values.mediumFontSize : Values.largeFontSize)
        publicKeyLabel.numberOfLines = 0
        publicKeyLabel.textAlignment = .center
        publicKeyLabel.lineBreakMode = .byCharWrapping
        publicKeyLabel.text = userHexEncodedPublicKey
        // Set up share button
        let shareButton = Button(style: .regular, size: .medium)
        shareButton.setTitle(NSLocalizedString("share", comment: ""), for: UIControl.State.normal)
        shareButton.addTarget(self, action: #selector(sharePublicKey), for: UIControl.Event.touchUpInside)
        // Set up button container
        let buttonContainer = UIStackView(arrangedSubviews: [ copyButton, shareButton ])
        buttonContainer.axis = .horizontal
        buttonContainer.spacing = Values.mediumSpacing
        buttonContainer.distribution = .fillEqually
        // Set up top stack view
        let topStackView = UIStackView(arrangedSubviews: [ headerStackView, separator, publicKeyLabel, buttonContainer ])
        topStackView.axis = .vertical
        topStackView.spacing = Values.largeSpacing
        topStackView.alignment = .fill
        topStackView.layoutMargins = UIEdgeInsets(top: 0, left: Values.largeSpacing, bottom: 0, right: Values.largeSpacing)
        topStackView.isLayoutMarginsRelativeArrangement = true
        // Set up setting buttons stack view
        let settingButtonsStackView = UIStackView(arrangedSubviews: getSettingButtons() )
        settingButtonsStackView.axis = .vertical
        settingButtonsStackView.alignment = .fill
        // Set up stack view
        let stackView = UIStackView(arrangedSubviews: [ topStackView, settingButtonsStackView ])
        stackView.axis = .vertical
        stackView.spacing = Values.largeSpacing
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: Values.mediumSpacing, left: 0, bottom: Values.mediumSpacing, right: 0)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.set(.width, to: UIScreen.main.bounds.width)
        // Set up scroll view
        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.addSubview(stackView)
        stackView.pin(to: scrollView)
        view.addSubview(scrollView)
        scrollView.pin(to: view)
        // Register for notifications
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppModeSwitchedNotification(_:)), name: .appModeSwitched, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func getSettingButtons() -> [UIView] {
        func getSeparator() -> UIView {
            let result = UIView()
            result.backgroundColor = Colors.separator
            result.set(.height, to: Values.separatorThickness)
            return result
        }
        func getSettingButton(withTitle title: String, color: UIColor, action selector: Selector) -> UIButton {
            let button = UIButton()
            button.setTitle(title, for: UIControl.State.normal)
            button.setTitleColor(color, for: UIControl.State.normal)
            button.titleLabel!.font = .boldSystemFont(ofSize: Values.mediumFontSize)
            button.titleLabel!.textAlignment = .center
            func getImage(withColor color: UIColor) -> UIImage {
                let rect = CGRect(origin: CGPoint.zero, size: CGSize(width: 1, height: 1))
                UIGraphicsBeginImageContext(rect.size)
                let context = UIGraphicsGetCurrentContext()!
                context.setFillColor(color.cgColor)
                context.fill(rect)
                let image = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                return image!
            }
            button.setBackgroundImage(getImage(withColor: Colors.buttonBackground), for: UIControl.State.normal)
            button.setBackgroundImage(getImage(withColor: Colors.settingButtonSelected), for: UIControl.State.highlighted)
            button.addTarget(self, action: selector, for: UIControl.Event.touchUpInside)
            button.set(.height, to: Values.settingButtonHeight)
            return button
        }
        var result = [
            getSeparator(),
            getSettingButton(withTitle: NSLocalizedString("vc_settings_privacy_button_title", comment: ""), color: Colors.text, action: #selector(showPrivacySettings)),
            getSeparator(),
            getSettingButton(withTitle: NSLocalizedString("vc_settings_notifications_button_title", comment: ""), color: Colors.text, action: #selector(showNotificationSettings))
        ]
        let isMasterDevice = UserDefaults.standard.isMasterDevice
        if isMasterDevice {
//            result.append(getSeparator())
//            result.append(getSettingButton(withTitle: NSLocalizedString("vc_settings_devices_button_title", comment: ""), color: Colors.text, action: #selector(showLinkedDevices)))
            result.append(getSeparator())
            result.append(getSettingButton(withTitle: NSLocalizedString("vc_settings_recovery_phrase_button_title", comment: ""), color: Colors.text, action: #selector(showSeed)))
        }
        result.append(getSeparator())
        result.append(getSettingButton(withTitle: NSLocalizedString("vc_settings_clear_all_data_button_title", comment: ""), color: Colors.destructive, action: #selector(clearAllData)))
        result.append(getSeparator())
        return result
    }
    
    // MARK: General
    @objc private func enableCopyButton() {
        copyButton.isUserInteractionEnabled = true
        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyButton.setTitle(NSLocalizedString("copy", comment: ""), for: UIControl.State.normal)
        }, completion: nil)
    }
    
    func avatarActionSheetTitle() -> String? {
        return "Update Profile Picture"
    }
    
    func fromViewController() -> UIViewController {
        return self
    }
    
    func hasClearAvatarAction() -> Bool {
        return false
    }
    
    func clearAvatarActionLabel() -> String {
        return "Clear"
    }
    
    // MARK: Updating
    @objc private func handleAppModeSwitchedNotification(_ notification: Notification) {
        updateNavigationBarButtons()
        // TODO: Redraw UI
    }

    private func handleIsEditingDisplayNameChanged() {
        updateNavigationBarButtons()
        UIView.animate(withDuration: 0.25) {
            self.displayNameLabel.alpha = self.isEditingDisplayName ? 0 : 1
            self.displayNameTextField.alpha = self.isEditingDisplayName ? 1 : 0
        }
        if isEditingDisplayName {
            displayNameTextField.becomeFirstResponder()
        } else {
            displayNameTextField.resignFirstResponder()
        }
    }
    
    private func updateNavigationBarButtons() {
        if isEditingDisplayName {
            let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(handleCancelDisplayNameEditingButtonTapped))
            cancelButton.tintColor = Colors.text
            navigationItem.leftBarButtonItem = cancelButton
            let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(handleSaveDisplayNameButtonTapped))
            doneButton.tintColor = Colors.text
            navigationItem.rightBarButtonItem = doneButton
        } else {
            let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
            closeButton.tintColor = Colors.text
            navigationItem.leftBarButtonItem = closeButton
            let appModeIcon = UserDefaults.standard[.isUsingDarkMode] ? #imageLiteral(resourceName: "ic_dark_theme_on") : #imageLiteral(resourceName: "ic_dark_theme_off")
            let appModeButton = UIBarButtonItem(image: appModeIcon, style: .plain, target: self, action: #selector(switchAppMode))
            appModeButton.tintColor = Colors.text
            let qrCodeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "QRCode"), style: .plain, target: self, action: #selector(showQRCode))
            qrCodeButton.tintColor = Colors.text
            navigationItem.rightBarButtonItems = [ qrCodeButton/*, appModeButton*/ ]
        }
    }
    
    func avatarDidChange(_ image: UIImage) {
        let maxSize = Int(kOWSProfileManager_MaxAvatarDiameter)
        profilePictureToBeUploaded = image.resizedImage(toFillPixelSize: CGSize(width: maxSize, height: maxSize))
        updateProfile(isUpdatingDisplayName: false, isUpdatingProfilePicture: true)
    }
    
    func clearAvatar() {
        profilePictureToBeUploaded = nil
        updateProfile(isUpdatingDisplayName: false, isUpdatingProfilePicture: true)
    }
    
    private func updateProfile(isUpdatingDisplayName: Bool, isUpdatingProfilePicture: Bool) {
        let displayName = displayNameToBeUploaded ?? OWSProfileManager.shared().profileNameForRecipient(withID: userHexEncodedPublicKey)
        let profilePicture = profilePictureToBeUploaded ?? OWSProfileManager.shared().profileAvatar(forRecipientId: userHexEncodedPublicKey)
        ModalActivityIndicatorViewController.present(fromViewController: navigationController!, canCancel: false) { [weak self] modalActivityIndicator in
            OWSProfileManager.shared().updateLocalProfileName(displayName, avatarImage: profilePicture, success: {
                DispatchQueue.main.async {
                    modalActivityIndicator.dismiss {
                        guard let self = self else { return }
                        self.profilePictureView.update()
                        self.displayNameLabel.text = displayName
                        self.profilePictureToBeUploaded = nil
                        self.displayNameToBeUploaded = nil
                    }
                }
            }, failure: { error in
                DispatchQueue.main.async {
                    modalActivityIndicator.dismiss {
                        var isMaxFileSizeExceeded = false
                        if let error = error as? DotNetAPI.DotNetAPIError {
                            isMaxFileSizeExceeded = (error == .maxFileSizeExceeded)
                        }
                        let title = isMaxFileSizeExceeded ? "Maximum File Size Exceeded" : "Couldn't Update Profile"
                        let message = isMaxFileSizeExceeded ? "Please select a smaller photo and try again" : "Please check your internet connection and try again"
                        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
                        self?.present(alert, animated: true, completion: nil)
                    }
                }
            }, requiresSync: true)
        }
    }
    
    // MARK: Interaction
    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func switchAppMode() {
        let isUsingDarkMode = UserDefaults.standard[.isUsingDarkMode]
        UserDefaults.standard[.isUsingDarkMode] = !isUsingDarkMode
        NotificationCenter.default.post(name: .appModeSwitched, object: nil)
    }

    @objc private func showQRCode() {
        let qrCodeVC = QRCodeVC()
        navigationController!.pushViewController(qrCodeVC, animated: true)
    }
    
    @objc private func handleCancelDisplayNameEditingButtonTapped() {
        isEditingDisplayName = false
    }
    
    @objc private func handleSaveDisplayNameButtonTapped() {
        func showError(title: String, message: String = "") {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
            presentAlert(alert)
        }
        let displayName = displayNameTextField.text!.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !displayName.isEmpty else {
            return showError(title: NSLocalizedString("vc_settings_display_name_missing_error", comment: ""))
        }
        guard !OWSProfileManager.shared().isProfileNameTooLong(displayName) else {
            return showError(title: NSLocalizedString("vc_settings_display_name_too_long_error", comment: ""))
        }
        isEditingDisplayName = false
        displayNameToBeUploaded = displayName
        updateProfile(isUpdatingDisplayName: true, isUpdatingProfilePicture: false)
    }
    
    @objc private func showEditProfilePictureUI() {
        profilePictureUtilities.showChangeAvatarUI()
    }
    
    @objc private func showEditDisplayNameUI() {
        isEditingDisplayName = true
    }
    
    @objc private func copyPublicKey() {
        UIPasteboard.general.string = userHexEncodedPublicKey
        copyButton.isUserInteractionEnabled = false
        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyButton.setTitle("Copied", for: UIControl.State.normal)
        }, completion: nil)
        Timer.scheduledTimer(timeInterval: 4, target: self, selector: #selector(enableCopyButton), userInfo: nil, repeats: false)
    }
    
    @objc private func sharePublicKey() {
        let shareVC = UIActivityViewController(activityItems: [ userHexEncodedPublicKey ], applicationActivities: nil)
        navigationController!.present(shareVC, animated: true, completion: nil)
    }
    
    @objc private func showPrivacySettings() {
        let privacySettingsVC = PrivacySettingsTableViewController()
        navigationController!.pushViewController(privacySettingsVC, animated: true)
    }
    
    @objc private func showNotificationSettings() {
        let notificationSettingsVC = NotificationSettingsViewController()
        navigationController!.pushViewController(notificationSettingsVC, animated: true)
    }
    
    @objc private func showLinkedDevices() {
        let deviceLinksVC = DeviceLinksVC()
        navigationController!.pushViewController(deviceLinksVC, animated: true)
    }
    
    @objc private func showSeed() {
        let seedModal = SeedModal()
        seedModal.modalPresentationStyle = .overFullScreen
        seedModal.modalTransitionStyle = .crossDissolve
        present(seedModal, animated: true, completion: nil)
    }
    
    @objc private func clearAllData() {
        let nukeDataModal = NukeDataModal()
        nukeDataModal.modalPresentationStyle = .overFullScreen
        nukeDataModal.modalTransitionStyle = .crossDissolve
        present(nukeDataModal, animated: true, completion: nil)
    }
}
