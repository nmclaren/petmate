
import React, { Component, StatelessComponent as SFC } from 'react';
import { connect } from 'react-redux'

import { electron, fs, path } from '../utils/electronImports'
import Modal from '../components/Modal';
import { RootState } from '../redux/types';
import { Toolbar, PropsFromDispatch } from '../redux/toolbar';

const ModalTitle: SFC<{}> = ({children}) => <h2>{children}</h2>

const GITHUB_URL = 'https://github.com/nmclaren/petmate';

// The X.Y.Z version comes from the app metadata (set at package time by
// build.sh via electron-builder's extraMetadata).  The build number is
// injected into the packaged app's package.json as 'buildNumber'; running
// from sources shows 'dev' instead.
function getVersionInfo() {
  const app = electron.remote.app;
  let buildNumber = 'dev';
  try {
    const pkg = JSON.parse(fs.readFileSync(path.resolve(app.getAppPath(), 'package.json'), 'utf-8'));
    if (pkg.buildNumber !== undefined) {
      buildNumber = String(pkg.buildNumber);
    }
  } catch (e) {
    console.error('failed to read package.json for build number', e);
  }
  return { version: app.getVersion(), buildNumber };
}

interface AboutModalProps {
  showAbout: boolean;
}

interface AboutModalDispatch {
  Toolbar: PropsFromDispatch;
}

class AboutModal_ extends Component<AboutModalProps & AboutModalDispatch> {
  handleOK = () => {
    this.props.Toolbar.setShowAbout(false);
  }

  handleClickGithub = (e: React.MouseEvent) => {
    e.preventDefault();
    electron.shell.openExternal(GITHUB_URL);
  }

  render () {
    const { version, buildNumber } = getVersionInfo();
    return (
      <div>
        <Modal showModal={this.props.showAbout}>
          <div style={{
            display: 'flex',
            height: '100%',
            flexDirection: 'column',
            justifyContent: 'space-between',
            color: 'var(--main-text-color)'
          }}>
            <div>
              <ModalTitle>Petmate - Ultimate Edition</ModalTitle>
              <div>Version {version} ({buildNumber})</div>
              <br/>
              <div>Original Petmate Copyright (c) 2026 Janne Hellsten</div>
              <div style={{fontStyle: 'italic'}}>Ultimate Edition customizations by Nick McLaren</div>
              <div>
                <a href={GITHUB_URL} onClick={this.handleClickGithub}>github.com/nmclaren/petmate</a>
              </div>
            </div>
            <div style={{alignSelf: 'flex-end'}}>
              <button className='primary' onClick={this.handleOK}>OK</button>
            </div>
          </div>
        </Modal>
      </div>
    )
  }
}

export default connect(
  (state: RootState) => {
    return {
      showAbout: state.toolbar.showAbout
    }
  },
  (dispatch) => {
    return {
      Toolbar: Toolbar.bindDispatch(dispatch)
    }
  }
)(AboutModal_)
