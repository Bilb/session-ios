
final class SearchBar : UISearchBar {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        update()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        update()
    }
    
    private func update() {
        searchBarStyle = .minimal // Hide the border around the search bar
        barStyle = .black // Use Apple's black design as a base
        tintColor = Colors.accent // The cursor color
        let searchImage = #imageLiteral(resourceName: "searchbar_search").asTintedImage(color: Colors.searchBarPlaceholder)!
        setImage(searchImage, for: .search, state: .normal)
        let clearImage = #imageLiteral(resourceName: "searchbar_clear").asTintedImage(color: Colors.searchBarPlaceholder)!
        setImage(clearImage, for: .clear, state: .normal)
        searchTextField.backgroundColor = Colors.searchBarBackground // The search bar background color
        searchTextField.textColor = Colors.text
        searchTextField.attributedPlaceholder = NSAttributedString(string: NSLocalizedString("Search", comment: ""), attributes: [ .foregroundColor : Colors.searchBarPlaceholder ])
        searchTextField.keyboardAppearance = .dark
        setPositionAdjustment(UIOffset(horizontal: 4, vertical: 0), for: UISearchBar.Icon.search)
        searchTextPositionAdjustment = UIOffset(horizontal: 2, vertical: 0)
        setPositionAdjustment(UIOffset(horizontal: -4, vertical: 0), for: UISearchBar.Icon.clear)
        searchTextField.removeConstraints(searchTextField.constraints)
        searchTextField.pin(.leading, to: .leading, of: searchTextField.superview!, withInset: Values.mediumSpacing + 3)
        searchTextField.pin(.top, to: .top, of: searchTextField.superview!, withInset: 10)
        searchTextField.superview!.pin(.trailing, to: .trailing, of: searchTextField, withInset: Values.mediumSpacing + 3)
        searchTextField.superview!.pin(.bottom, to: .bottom, of: searchTextField, withInset: 10)
        searchTextField.set(.height, to: Values.searchBarHeight)
        searchTextField.set(.width, to: UIScreen.main.bounds.width - 2 * Values.mediumSpacing)
    }
}
